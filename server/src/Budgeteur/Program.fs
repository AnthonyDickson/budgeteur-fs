module Budgeteur.Program

open System.Diagnostics
open System.Reflection
open System.Threading.Tasks

open DbUp
open Microsoft.AspNetCore.Builder
open Microsoft.AspNetCore.Hosting
open Microsoft.AspNetCore.Http
open Microsoft.AspNetCore.HttpOverrides
open Microsoft.Data.Sqlite
open Microsoft.Extensions.DependencyInjection
open Microsoft.Extensions.Hosting
open Microsoft.Extensions.Logging
open Microsoft.Extensions.Options
open Oxpecker
open Serilog

open Budgeteur.Data.Db
open Budgeteur.Shared.ApiError
open Budgeteur.Shared.Auth
open Budgeteur.Shared.Clock
open Budgeteur.Shared.Config
open Budgeteur.Shared.Json
open Budgeteur.Shared.Logging
open Budgeteur.Shared.OpenApi
open Budgeteur.Shared.RequestLogging
open Budgeteur.Feature.Account
open Budgeteur.Feature.Auth
open Budgeteur.Feature.AutoTag
open Budgeteur.Feature.BalanceSheet
open Budgeteur.Feature.Dashboard
open Budgeteur.Feature.Import
open Budgeteur.Feature.QuickTag
open Budgeteur.Feature.Report
open Budgeteur.Feature.Rule
open Budgeteur.Feature.Status
open Budgeteur.Feature.Tag
open Budgeteur.Feature.TestSupport
open Budgeteur.Feature.Transaction


let private applyMigrations (connectionString : string) =
    let result =
        DeployChanges.To
            .SqliteDatabase(connectionString)
            .WithScriptsEmbeddedInAssembly(Assembly.GetExecutingAssembly ())
            .LogToConsole()
            .Build()
            .PerformUpgrade()

    if not result.Successful then
        failwithf "Database migration failed: %O" result.Error

    use conn = new SqliteConnection (connectionString)
    conn.Open ()

    // WAL is stored in the database file, so setting it once applies to every
    // later connection. Foreign keys are per connection and are set in the
    // connection string (Config.withForeignKeys).
    use walCmd = conn.CreateCommand ()
    walCmd.CommandText <- "PRAGMA journal_mode = WAL"
    walCmd.ExecuteNonQuery () |> ignore

let private handleException
    (loggerFactory : ILoggerFactory)
    (next : RequestDelegate)
    : RequestDelegate =
    let logger = loggerFactory.CreateLogger "Budgeteur.Program"

    RequestDelegate (fun (ctx : HttpContext) ->
        task {
            try
                return! next.Invoke ctx
            with ex ->
                logger.LogError (ex, "An unhandled exception occurred")

                ctx.Response.StatusCode <- 500

                return!
                    Json.write ctx {
                        Error = "Internal Server Error"
                        Details = "An unexpected error occurred"
                        StatusCode = Some 500
                        RequestId = ctx.TraceIdentifier
                    }
        }
        :> Task)

let private configureForwardedHeaders
    (options : ForwardedHeadersOptions)
    : unit =
    options.ForwardedHeaders <-
        ForwardedHeaders.XForwardedFor ||| ForwardedHeaders.XForwardedProto

    options.KnownIPNetworks.Clear ()
    options.KnownProxies.Clear ()

    // Trust common Docker/private network ranges
    options.KnownIPNetworks.Add (System.Net.IPNetwork.Parse "10.0.0.0/8")
    options.KnownIPNetworks.Add (System.Net.IPNetwork.Parse "172.16.0.0/12")
    options.KnownIPNetworks.Add (System.Net.IPNetwork.Parse "192.168.0.0/16")

let private withAuth endpoints =
    Seq.map (addFilter Auth.requireAuth) endpoints

let private buildEndpoints
    (connectionString : string)
    (loginReturnUrl : string)
    (app : WebApplication)
    =
    let queryContext = QueryContextFactory.Create connectionString
    let startedAt = Process.GetCurrentProcess().StartTime.ToUniversalTime()

    let authEndpoints =
        seq [ GET [ Login.endpoint loginReturnUrl; Logout.endpoint "/" ] ]

    let statusEndpoints = [
        GET [
            GetStatus.endpoint
                connectionString
                app.Environment.EnvironmentName
                startedAt
        ]
    ]

    let featureEndpoints =
        Seq.concat [
            AccountEndpoints.all queryContext Clock.system
            AutoTagEndpoints.all queryContext
            BalanceSheetEndpoints.all queryContext Clock.system
            DashboardEndpoints.all queryContext
            ImportEndpoints.all queryContext
            ReportEndpoints.all queryContext
            QuickTagEndpoints.all queryContext
            RuleEndpoints.all queryContext
            TransactionEndpoints.all queryContext
            TagEndpoints.all queryContext
        ]
        |> withAuth

    // Test-only helpers, available in Development only (mirrors the Scalar
    // docs gating below) so they can never be reached against real data.
    let testEndpoints =
        if app.Environment.IsDevelopment () then
            Seq.concat [
                [ DELETE [ ResetUserData.endpoint queryContext ] ]
                BalanceSheetEndpoints.developmentOnly queryContext
            ]
            |> withAuth
        else
            Seq.empty

    Seq.concat [
        authEndpoints
        statusEndpoints
        featureEndpoints
        testEndpoints
    ]


let private configureBuilder
    (builder : WebApplicationBuilder)
    (config : AppConfig)
    : unit =
    let isDevelopment = builder.Environment.IsDevelopment ()

    Auth.configureServices builder.Services isDevelopment config.Oidc
    builder.Services.AddRouting().AddOxpecker() |> ignore

    builder.Services.Configure<ForwardedHeadersOptions>
        configureForwardedHeaders
    |> ignore

    builder.Services.Configure<HostOptions>(fun (options : HostOptions) ->
        options.ShutdownTimeout <- System.TimeSpan.FromSeconds 30L)
    |> ignore

    builder.WebHost.ConfigureKestrel (fun options ->
        options.Limits.MaxRequestBodySize <- 65536L)
    |> ignore

    builder.Host.UseSerilog (Logging.configure GetStatus.Path config.Logging)
    |> ignore

    match config.Oauth2 with
    | Some config when isDevelopment ->
        OpenApi.configureServices builder.Services config
    | _ -> ()

let private configureApp (app : WebApplication) (config : AppConfig) : unit =
    let isDevelopment = app.Environment.IsDevelopment ()

    match config.Oauth2 with
    | Some config when isDevelopment -> OpenApi.mapEndpoints app config.ClientId
    | _ -> ()

    app.Use (
        handleException (app.Services.GetRequiredService<ILoggerFactory>())
    )
    |> ignore

    app.UseForwardedHeaders () |> ignore
    app.UseStaticFiles () |> ignore
    app.UseRouting () |> ignore
    app.UseAuthentication () |> ignore

    app.Use (
        Middleware.requestLogging (
            (app.Services.GetRequiredService<Serilog.ILogger>())
                .ForContext("SourceContext", "Budgeteur.Request")
        )
    )
    |> ignore

    app.UseAuthorization () |> ignore

    app.UseOxpecker (
        buildEndpoints config.ConnectionString config.Login.ReturnUrl app
    )
    |> ignore

    // Run the vite dev server for accessing the SPA bundle in the dev
    // environment. The fallback is explicitly disabled to avoid surprising and
    // difficult to debug situations where the backend is not loading the code
    // you expect.
    if not isDevelopment then
        app.MapFallbackToFile "index.html" |> ignore

[<EntryPoint>]
let main (args : string array) : int =
    let builder = WebApplication.CreateBuilder args

    let config =
        try
            Config.load builder.Services builder.Configuration
        with :? OptionsValidationException as ex ->
            eprintfn
                "The server refused to start: configuration validation failed."

            ex.Failures |> Seq.iter (fun failure -> eprintfn "  - %s" failure)

            eprintfn
                "Fix the settings above and restart. Values are read from \
                appsettings.json or environment variables (e.g. \
                Oidc__ClientSecret)."

            exit 1

    configureBuilder builder config

    let app = builder.Build ()
    configureApp app config

    applyMigrations config.ConnectionString

    app.Run ()
    0
