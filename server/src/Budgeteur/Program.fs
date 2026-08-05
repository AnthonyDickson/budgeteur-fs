module Budgeteur.Program

open System.Collections.Generic
open System.ComponentModel.DataAnnotations
open System.Reflection
open System.Threading.Tasks

open DbUp
open Microsoft.AspNetCore.Builder
open Microsoft.AspNetCore.Hosting
open Microsoft.AspNetCore.Http
open Microsoft.AspNetCore.HttpOverrides
open Microsoft.Data.Sqlite
open Microsoft.Extensions.Configuration
open Microsoft.Extensions.DependencyInjection
open Microsoft.Extensions.Hosting
open Microsoft.Extensions.Logging
open Microsoft.OpenApi
open Oxpecker
open Oxpecker.OpenApi
open Scalar.AspNetCore
open Serilog
open Serilog.Formatting.Compact

open Budgeteur.ApiError
open Budgeteur.Auth
open Budgeteur.Config
open Budgeteur.Json
open Budgeteur.OpenApi
open Budgeteur.Transactions


let private addOpenApiToBuilder (builder : WebApplicationBuilder) (ouath2 : OAuth2Options) =
    let oauth2AuthUrl = ouath2.AuthorizationUrl
    let oauth2TokenUrl = ouath2.TokenUrl

    builder.Services.AddOpenApi (fun options ->
        options.AddSchemaTransformer<FSharpOptionSchemaTransformer> () |> ignore
        options.AddSchemaTransformer<OpenApi.FSharpRecordSchemaTransformer> () |> ignore

        options.AddSchemaTransformer<OpenApi.DateTimeAsUnixTimestampTransformer> ()
        |> ignore

        options.AddSchemaTransformer<OpenApi.XmlDocSchemaTransformer> () |> ignore

        options.AddDocumentTransformer (fun doc _ _ ->
            if isNull doc.Components then
                doc.Components <- OpenApiComponents ()

            if isNull doc.Components.SecuritySchemes then
                doc.Components.SecuritySchemes <- Dictionary<string, IOpenApiSecurityScheme> ()

            doc.Components.SecuritySchemes["bearerAuth"] <-
                OpenApiSecurityScheme (
                    Type = SecuritySchemeType.Http,
                    Scheme = "bearer",
                    BearerFormat = "JWT",
                    Description = "JWT access token from Authelia. Use the Scalar OAuth2 flow to obtain one."
                )

            doc.Components.SecuritySchemes["scalarOAuth2"] <-
                OpenApiSecurityScheme (
                    Type = SecuritySchemeType.OAuth2,
                    Flows =
                        OpenApiOAuthFlows (
                            AuthorizationCode =
                                OpenApiOAuthFlow (
                                    AuthorizationUrl = System.Uri oauth2AuthUrl,
                                    TokenUrl = System.Uri oauth2TokenUrl
                                )
                        )
                )

            doc.Security <- ResizeArray [ Auth.oauthRequirement doc ]

            Task.CompletedTask)
        |> ignore)
    |> ignore

let private addOpenApiToApp (app : WebApplication) (clientId : string) =
    app.MapOpenApi () |> ignore

    app.MapScalarApiReference (fun opts ->
        opts
            .WithTitle("Budgeteur API")
            .WithTheme(ScalarTheme.DeepSpace)
            .WithDefaultHttpClient (ScalarTarget.Http, ScalarClient.Curl)
        |> ignore

        opts
            .AddPreferredSecuritySchemes([| "scalarOAuth2" |])
            .AddAuthorizationCodeFlow (
                "scalarOAuth2",
                fun flow ->
                    flow.ClientId <- clientId
                    flow.Pkce <- Pkce.Sha256
                    flow.SelectedScopes <- [| "openid"; "profile"; "email" |]
            )
        |> ignore)
    |> ignore

let private applyMigrations (connectionString : string) =
    let result =
        DeployChanges.To
            .SqliteDatabase(connectionString)
            .WithScriptsEmbeddedInAssembly(Assembly.GetExecutingAssembly ())
            .LogToConsole()
            .Build()
            .PerformUpgrade ()

    if not result.Successful then
        failwithf "Database migration failed: %O" result.Error

    use conn = new SqliteConnection (connectionString)
    conn.Open ()

    use walCmd = conn.CreateCommand ()
    walCmd.CommandText <- "PRAGMA journal_mode = WAL"
    walCmd.ExecuteNonQuery () |> ignore

    use fkCmd = conn.CreateCommand ()
    fkCmd.CommandText <- "PRAGMA foreign_keys = ON"
    fkCmd.ExecuteNonQuery () |> ignore

let private handleException (loggerFactory : ILoggerFactory) (next : RequestDelegate) : RequestDelegate =
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

let configureSerilog (loggingOptions : LoggingOptions) (ctx : HostBuilderContext) (config : LoggerConfiguration) =
    let filePath =
        loggingOptions.FilePath
        |> Option.ofObj
        |> Option.filter (not << System.String.IsNullOrWhiteSpace)

    config.MinimumLevel.Information().WriteTo.Console (RenderedCompactJsonFormatter ())
    |> ignore

    match filePath with
    | Some path -> config.WriteTo.File (RenderedCompactJsonFormatter (), path) |> ignore
    | None -> ()

let private configureForwardedHeaders (options : ForwardedHeadersOptions) : unit =
    options.ForwardedHeaders <- ForwardedHeaders.XForwardedFor ||| ForwardedHeaders.XForwardedProto
    options.KnownIPNetworks.Clear ()
    options.KnownProxies.Clear ()

    // Trust common Docker/private network ranges
    options.KnownIPNetworks.Add (System.Net.IPNetwork.Parse "10.0.0.0/8")
    options.KnownIPNetworks.Add (System.Net.IPNetwork.Parse "172.16.0.0/12")
    options.KnownIPNetworks.Add (System.Net.IPNetwork.Parse "192.168.0.0/16")

[<EntryPoint>]
let main (args : string array) : int =
    let builder = WebApplication.CreateBuilder args
    let isDevelopment = builder.Environment.IsDevelopment ()

    let oidcOptions =
        Config.readSection<OidcOptions> builder.Services builder.Configuration "Oidc"

    let oauthOptions =
        if isDevelopment then
            Config.readSection<OAuth2Options> builder.Services builder.Configuration "OAuth2"
            |> Some
        else
            None

    let loginOptions =
        Config.readSection<LoginOptions> builder.Services builder.Configuration "Login"

    let loggingOptions =
        Config.readSection<LoggingOptions> builder.Services builder.Configuration "Logging"

    Auth.configureServices builder.Services (builder.Environment.IsDevelopment ()) oidcOptions

    builder.Services.AddRouting().AddOxpecker () |> ignore

    builder.Services.Configure<ForwardedHeadersOptions> configureForwardedHeaders
    |> ignore

    builder.Services.Configure<HostOptions> (fun (options : HostOptions) ->
        options.ShutdownTimeout <- System.TimeSpan.FromSeconds 30L)
    |> ignore

    builder.WebHost.ConfigureKestrel (fun options -> options.Limits.MaxRequestBodySize <- 65536L)
    |> ignore

    builder.Host.UseSerilog (configureSerilog loggingOptions) |> ignore

    oauthOptions
    |> Option.iter (fun oauthOptions -> addOpenApiToBuilder builder oauthOptions)

    let app = builder.Build ()
    let isDevelopment = app.Environment.IsDevelopment ()

    let connectionString = app.Configuration.GetConnectionString "Default"
    applyMigrations connectionString

    oauthOptions
    |> Option.iter (fun oauthOptions -> addOpenApiToApp app oauthOptions.ClientId)

    let loginReturnUrl =
        loginOptions.ReturnUrl |> Option.ofObj |> Option.defaultValue "/"

    let authEndpoints = Auth.endpoints loginReturnUrl
    let transactionEndpoints = Transactions.endpoints connectionString
    let allEndpoints = Seq.concat [ authEndpoints; transactionEndpoints ]

    app.Use (handleException (app.Services.GetRequiredService<ILoggerFactory> ()))
    |> ignore

    app.UseForwardedHeaders () |> ignore
    app.UseStaticFiles () |> ignore
    app.UseRouting () |> ignore
    app.UseAuthentication () |> ignore

    app.Use (
        RequestLogging.Middleware.requestLogging (
            (app.Services.GetRequiredService<Serilog.ILogger> ()).ForContext ("SourceContext", "Budgeteur.Request")
        )
    )
    |> ignore

    app.UseAuthorization () |> ignore
    app.UseOxpecker allEndpoints |> ignore

    // Run the vite dev server for accessing the SPA bundle in the dev environment.
    if not isDevelopment then
        app.MapFallbackToFile "index.html" |> ignore

    app.Run ()
    0
