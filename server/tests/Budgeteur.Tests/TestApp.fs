namespace Budgeteur.Tests

open System
open System.Net.Http
open System.Security.Claims
open System.Threading.Tasks
open Microsoft.AspNetCore.Builder
open Microsoft.AspNetCore.Hosting
open Microsoft.AspNetCore.TestHost
open Microsoft.Data.Sqlite
open Microsoft.Extensions.DependencyInjection
open Microsoft.Extensions.Hosting
open Microsoft.AspNetCore.Http
open Oxpecker

module private TestClaims =
    let userId = "test-user"

    /// The header a request can carry to act as a different user against the same
    /// database. Used by the cross-user scoping tests.
    let header = "X-Test-User"

    let principal (userId : string) =
        let identity = ClaimsIdentity ([ Claim ("sub", userId) ], "test")
        ClaimsPrincipal identity

type TestAppConfig = {
    EndpointProviders : (Budgeteur.Data.Db.QueryContextFactory -> Oxpecker.RoutingTypes.Endpoint list) list
    CleanTables : string list
}

/// Each `with*` routes a slice's production endpoint groups, minus the auth filter.
module TestAppConfig =
    open Budgeteur.Data.Db
    open Budgeteur.Feature.BalanceSheet
    open Budgeteur.Feature.IncomeStatement
    open Budgeteur.Feature.Rule
    open Budgeteur.Feature.Tag
    open Budgeteur.Feature.TestSupport
    open Budgeteur.Feature.Transaction

    let empty = {
        EndpointProviders = []
        CleanTables = []
    }

    let private withEndpoints
        (tables : string list)
        (provider : QueryContextFactory -> Oxpecker.RoutingTypes.Endpoint list)
        (config : TestAppConfig)
        = {
        EndpointProviders = provider :: config.EndpointProviders
        CleanTables = tables @ config.CleanTables
    }

    let withTransactions = withEndpoints [ "Transactions" ] TransactionEndpoints.all

    let withTags = withEndpoints [ "Tags" ] TagEndpoints.all

    let withRules = withEndpoints [ "Rules" ] RuleEndpoints.all

    let withIncomeStatement = withEndpoints [] IncomeStatementEndpoints.all

    /// Includes the development-only item reads, which the tests use to observe item state.
    let withBalanceSheet (clock : Clock) =
        withEndpoints [ "BalanceSheetItems"; "BalanceSheets" ] (fun queryContext ->
            BalanceSheetEndpoints.all queryContext clock
            @ BalanceSheetEndpoints.developmentOnly queryContext)

    let withResetUserData =
        withEndpoints [] (fun queryContext -> [ DELETE [ ResetUserData.endpoint queryContext ] ])

type TestApp = {
    Client : HttpClient
    /// The app's database, for state the API cannot set or read (e.g. an import hash).
    ConnectionString : string
    /// A second client authenticated as a different user against the same database.
    ClientForUser : string -> HttpClient
    CleanDatabase : unit -> unit
    Dispose : unit -> unit
} with

    interface IDisposable with
        member this.Dispose () = this.Dispose ()

module TestApp =
    open Budgeteur.Data.Db
    open Budgeteur.Shared.RequestLogging
    open Budgeteur.Domain.Transaction

    /// Serialises request-log dumps across concurrent tests so their output can't interleave.
    let private dumpLock = obj ()

    /// Print the buffered request log to stderr for 5xx responses, so a failing test shows the
    /// real server-side error (e.g. the SQLite exception) instead of an opaque 500 body. Messages
    /// can embed full stack traces — keep just the first line for readability.
    let private firstLine (message : string) =
        let idx = message.IndexOf '\n'

        if idx >= 0 then message.Substring (0, idx) else message

    let private dumpRequestLog (ctx : HttpContext) =
        let entries = (RequestLog.fromContext ctx).Entries

        if not (List.isEmpty entries) then
            let sb = System.Text.StringBuilder ()
            sb.AppendLine () |> ignore

            sb.AppendLine $"[TestApp] {ctx.Request.Method} {ctx.Request.Path.ToString ()} -> {ctx.Response.StatusCode}"
            |> ignore

            for entry in entries do
                sb.AppendLine $"  [{LogLevel.toString entry.Level}] {firstLine entry.Message}"
                |> ignore

            // Build the whole block first, then write it in one call under a lock so concurrent
            // test requests can't interleave their output mid-line.
            lock dumpLock (fun () -> eprintf "%s" (sb.ToString ()))

    /// The `sub` claim to authenticate a request as: the `X-Test-User` header when
    /// present, otherwise the default test user.
    let private requestUser (ctx : HttpContext) (defaultUser : string) =
        let header = ctx.Request.Headers[TestClaims.header]

        if header.Count > 0 && not (String.IsNullOrWhiteSpace header[0]) then
            string header[0]
        else
            defaultUser

    /// Create an app server with an in-memory SQLite database
    let create (config : TestAppConfig) =
        // In-memory database shared by every connection through SQLite's shared cache. The keeper
        // connection must stay open for the lifetime of the app — the in-memory DB is dropped when
        // the last connection to it closes. Each query opens its own connection, so disposing a
        // QueryContext (which closes its connection) doesn't lose the data.
        let name = $"test-{Guid.NewGuid ()}"

        let connectionString =
            Budgeteur.Shared.Config.Config.withForeignKeys $"Data Source=file:{name}?mode=memory&cache=shared"

        let keeper = new SqliteConnection (connectionString)
        keeper.Open ()

        let queryContext = QueryContextFactory.Create connectionString

        let endpoints =
            config.EndpointProviders |> Seq.collect (fun provider -> provider queryContext)

        let result =
            DbUp.DeployChanges.To
                .SqliteDatabase(connectionString)
                // We need to access server assembly for the migration scripts.
                .WithScriptsEmbeddedInAssembly(typeof<Transaction>.Assembly)
                .Build()
                .PerformUpgrade()

        if not result.Successful then
            failwithf "Test database migration failed: %O" result.Error

        let host =
            HostBuilder()
                .ConfigureWebHost(fun webHostBuilder ->
                    webHostBuilder
                        .UseTestServer()
                        .ConfigureServices(fun services -> services.AddRouting().AddOxpecker() |> ignore)
                        .Configure(fun app ->
                            app.Use (fun (ctx : HttpContext) (next : Func<Task>) ->
                                task {
                                    ctx.Items[RequestLog.Key] <- RequestLog ()
                                    ctx.User <- TestClaims.principal (requestUser ctx TestClaims.userId)

                                    try
                                        return! next.Invoke ()
                                    finally
                                        if ctx.Response.StatusCode >= 500 then
                                            dumpRequestLog ctx
                                }
                                :> Task)
                            |> ignore

                            app.UseRouting().UseOxpecker endpoints |> ignore)
                    |> ignore)
                .Build()

        host.StartAsync().GetAwaiter().GetResult()

        let client = host.GetTestClient ()

        let clientForUser (userId : string) =
            let client = host.GetTestClient ()
            client.DefaultRequestHeaders.Add (TestClaims.header, userId)
            client

        let cleanDatabase () =
            use conn = new SqliteConnection (connectionString)
            conn.Open ()

            for table in config.CleanTables do
                use cmd = conn.CreateCommand ()
                cmd.CommandText <- $"DELETE FROM {table}"
                cmd.ExecuteNonQuery () |> ignore

        let dispose () =
            client.Dispose ()
            host.Dispose ()
            keeper.Dispose ()

        {
            Client = client
            ConnectionString = connectionString
            ClientForUser = clientForUser
            CleanDatabase = cleanDatabase
            Dispose = dispose
        }
