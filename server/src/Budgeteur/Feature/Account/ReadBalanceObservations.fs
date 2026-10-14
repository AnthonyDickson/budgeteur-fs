namespace Budgeteur.Feature.Account

module ReadBalanceObservations =
    open System
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi
    open SqlHydra.Query

    open Budgeteur.Data
    open Budgeteur.Data.Db
    open Budgeteur.Domain.Money
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/accounts/{%O:guid}/observations"

    /// <summary>The user's account's observations, newest first, or none when
    /// the user has no account with the id.</summary>
    let private read
        (queryContext : QueryContextFactory)
        (userId : string)
        (accountId : Guid)
        =
        task {
            let! owned =
                selectTask queryContext {
                    for a in main.Accounts do
                        where (a.Id = accountId && a.UserId = userId)
                        count
                }

            if owned = 0 then
                return None
            else
                let! rows =
                    selectTask queryContext {
                        for o in main.BalanceObservations do
                            where (o.AccountId = accountId && o.UserId = userId)

                            orderByDescending o.AsOf
                    }

                return
                    rows
                    |> Seq.map BalanceObservationCodec.fromRow
                    |> List.ofSeq
                    |> Some
        }

    let private handler
        (queryContext : QueryContextFactory)
        (id : Guid)
        : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx

                let! observations =
                    read queryContext userId id
                    |> TaskResult.requireSome (
                        NotFound $"Account %O{id} not found"
                    )

                log.Info (
                    $"Returned %i{List.length observations} balances for \
                    account %O{id}",
                    LogProp.prop "accountId" (id.ToString ())
                )

                do!
                    observations
                    |> List.map (fun observation ->
                        ({
                            Balance = Money.value observation.Balance
                            AsOf = observation.AsOf
                        }
                        : AccountBalanceResponse))
                    |> Json.write ctx
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "List an account's balances"

        op.Description <-
            "Returns every balance recorded for the account, newest first. The \
            first is the current balance."

        op.Tags <- HashSet [ OpenApiTagReference "Accounts" ]

        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) =
        routef Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                responseBodies = [|
                    ResponseBody typeof<AccountBalanceResponse list>
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 404)
                |],
                configureOperation = configureOperation
            )
        )
