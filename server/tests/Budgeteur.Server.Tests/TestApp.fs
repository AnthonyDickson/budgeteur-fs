namespace Budgeteur.Server.Tests

open System
open System.IO
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
    open Budgeteur.Server

    let empty = {
        EndpointProviders = []
        CleanTables = []
    }

    let withTodos (config : TestAppConfig) = {
        config with
            EndpointProviders =
                (fun connStr -> Todos.Store.create connStr |> Todos.Api.endpoints)
                :: config.EndpointProviders
            CleanTables = "Todos" :: config.CleanTables
    }

    let withTransactions (config : TestAppConfig) = {
        config with
            EndpointProviders =
                (fun connStr -> Transactions.Store.create connStr |> Transactions.Api.endpoints)
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
    open Budgeteur.Server.RequestLogging

    let create (config : TestAppConfig) =
        let dbPath = Path.Combine (Path.GetTempPath (), $"test-todos-{Guid.NewGuid ()}.db")
        let connectionString = $"Data Source={dbPath}"

        let endpoints =
            config.EndpointProviders
            |> Seq.collect (fun provider -> provider connectionString)

        let result =
            DbUp.DeployChanges.To
                .SqliteDatabase(connectionString)
                .WithScriptsEmbeddedInAssembly(typeof<Budgeteur.Server.Todos.Todo>.Assembly)
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
                                    return! next.Invoke ()
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

            try
                File.Delete dbPath
            with _ ->
                ()

        {
            Client = client
            CleanDatabase = cleanDatabase
            Dispose = dispose
        }
