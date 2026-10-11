namespace Budgeteur.Feature.Account

module ReadAllAccounts =
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi

    open Budgeteur.Data.Db
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/accounts"

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                let! accounts = AccountQuery.readAll queryContext userId

                log.Info (
                    $"Returned %i{List.length accounts} accounts",
                    LogProp.prop "count" (List.length accounts)
                )

                do!
                    accounts
                    |> List.map (fun (account, current) ->
                        AccountResponse.fromDomain account current)
                    |> Json.write ctx
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "List all accounts"

        op.Description <-
            "Returns the user's accounts, by name, with their current balances."

        op.Tags <- HashSet [ OpenApiTagReference "Accounts" ]

        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) =
        route Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                responseBodies = [|
                    ResponseBody typeof<AccountResponse list>
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                |],
                configureOperation = configureOperation
            )
        )
