namespace LustreTodos.Server.Tests

open System
open System.IO
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
open LustreTodos.Server.RequestLogging
open LustreTodos.Server.Todos
open LustreTodos.Server.Todos.Store

module private TestClaims =
    let userId = "test-user"

    let principal =
        let identity = ClaimsIdentity ([ Claim ("sub", userId) ], "test")
        ClaimsPrincipal identity

type TestApp () =
    let dbPath = Path.Combine (Path.GetTempPath (), $"test-todos-{Guid.NewGuid ()}.db")

    let connectionString = $"Data Source={dbPath}"

    let store = create connectionString

    let endpoints = Api.endpoints store

    let host =
        do
            let result =
                DbUp.DeployChanges.To
                    .SqliteDatabase(connectionString)
                    .WithScriptsEmbeddedInAssembly(typeof<Todo>.Assembly)
                    .Build()
                    .PerformUpgrade ()

            if not result.Successful then
                failwithf "Test database migration failed: %O" result.Error

        let h =
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

        h.StartAsync().GetAwaiter().GetResult ()
        h

    let client = host.GetTestClient ()

    member _.Client = client

    member _.CleanDatabase () =
        use conn = new SqliteConnection (connectionString)
        conn.Open ()
        use cmd = conn.CreateCommand ()
        cmd.CommandText <- "DELETE FROM Todos"
        cmd.ExecuteNonQuery () |> ignore

    interface IDisposable with
        member _.Dispose () =
            client.Dispose ()
            host.Dispose ()

            try
                File.Delete dbPath
            with _ ->
                ()
