namespace Budgeteur.Feature.Account

module RecordBalance =
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
    open Budgeteur.Domain.Account
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.Clock
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/accounts/{%O:guid}/balances"

    /// <summary>Record the balance for the user's account and read the account
    /// back, in one database transaction. Fails with <c>NotFound</c> when the
    /// user has no account with the id.</summary>
    let private record
        (queryContext : QueryContextFactory)
        (userId : string)
        (accountId : Guid)
        (observation : BalanceObservation)
        =
        task {
            use! ctx = queryContext.OpenContextAsync ()
            ctx.BeginTransaction ()

            let! owned =
                selectTask ctx {
                    for a in main.Accounts do
                        where (a.Id = accountId && a.UserId = userId)
                        count
                }

            if owned = 0 then
                return Error (NotFound $"Account %O{accountId} not found")
            else
                do!
                    BalanceObservationStore.record
                        ctx
                        userId
                        accountId
                        observation

                let! recorded = AccountQuery.tryRead ctx userId accountId
                ctx.CommitTransaction ()

                return
                    recorded
                    |> Result.requireSome (
                        NotFound $"Account %O{accountId} not found"
                    )
        }

    let private handler
        (queryContext : QueryContextFactory)
        (clock : Clock)
        (id : Guid)
        : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                let! (req : BalanceEntryRequest) = Json.read ctx
                let! observation = AccountRequest.balance (clock ()) req
                let! account = record queryContext userId id observation

                log.Info (
                    $"Recorded a balance for account %O{id}",
                    LogProp.prop "accountId" (id.ToString ())
                )

                do! Json.write ctx (AccountResponse.fromDomain account)
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Record an account's balance"

        op.Description <-
            "Records the account's balance as of a date, replacing any balance \
            on that date. Returns the account with its current balance: the \
            latest by as-of date, so an older balance does not replace a newer \
            one."

        op.Tags <- HashSet [ OpenApiTagReference "Accounts" ]

        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) (clock : Clock) =
        routef Path (handler queryContext clock)
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<BalanceEntryRequest>,
                responseBodies = [|
                    ResponseBody typeof<AccountResponse>
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 404)
                |],
                configureOperation = configureOperation
            )
        )
