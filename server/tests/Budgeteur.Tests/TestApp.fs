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

    let principal =
        let identity = ClaimsIdentity ([ Claim ("sub", userId) ], "test")
        ClaimsPrincipal identity

type TestAppConfig = {
    EndpointProviders : (string -> Oxpecker.RoutingTypes.Endpoint seq) list
    CleanTables : string list
}

module TestAppConfig =
    open Budgeteur.Data.Db
    open Budgeteur.Feature.Transaction

    let empty = {
        EndpointProviders = []
        CleanTables = []
    }

    let withTransactions (config : TestAppConfig) = {
        config with
            EndpointProviders =
                (fun connStr ->
                    let queryContext = QueryContextFactory.Create connStr

                    [
                        GET [
                            ReadTransaction.endpoint queryContext
                            ReadAllTransactions.endpoint queryContext
                        ]
                        POST [ CreateTransaction.endpoint queryContext ]
                        PUT [ UpdateTransaction.endpoint queryContext ]
                        DELETE [ DeleteTransaction.endpoint queryContext ]
                    ])
                :: config.EndpointProviders
            CleanTables = "Transactions" :: config.CleanTables
    }

type TestApp = {
    Client : HttpClient
    CleanDatabase : unit -> unit
    Dispose : unit -> unit
} with

    interface IDisposable with
        member this.Dispose () = this.Dispose ()

module TestApp =
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

    /// Create an app server with an in-memory SQLite database
    let create (config : TestAppConfig) =
        // In-memory database shared by every connection through SQLite's shared cache. The keeper
        // connection must stay open for the lifetime of the app — the in-memory DB is dropped when
        // the last connection to it closes. Each query opens its own connection, so disposing a
        // QueryContext (which closes its connection) doesn't lose the data.
        let name = $"test-{Guid.NewGuid ()}"
        let connectionString = $"Data Source=file:{name}?mode=memory&cache=shared"
        let keeper = new SqliteConnection (connectionString)
        keeper.Open ()

        let endpoints =
            config.EndpointProviders
            |> Seq.collect (fun provider -> provider connectionString)

        let result =
            DbUp.DeployChanges.To
                .SqliteDatabase(connectionString)
                // We need to access server assembly for the migration scripts.
                .WithScriptsEmbeddedInAssembly(typeof<Transaction>.Assembly)
                .Build()
                .PerformUpgrade ()

        if not result.Successful then
            failwithf "Test database migration failed: %O" result.Error

        let host =
            HostBuilder()
                .ConfigureWebHost(fun webHostBuilder ->
                    webHostBuilder
                        .UseTestServer()
                        .ConfigureServices(fun services -> services.AddRouting().AddOxpecker () |> ignore)
                        .Configure (fun app ->
                            app.Use (fun (ctx : HttpContext) (next : Func<Task>) ->
                                task {
                                    ctx.Items[RequestLog.Key] <- RequestLog ()
                                    ctx.User <- TestClaims.principal

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
                .Build ()

        host.StartAsync().GetAwaiter().GetResult ()

        let client = host.GetTestClient ()

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
            CleanDatabase = cleanDatabase
            Dispose = dispose
        }
