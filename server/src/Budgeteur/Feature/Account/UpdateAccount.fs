namespace Budgeteur.Feature.Account

module UpdateAccount =
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
    let Path = "/api/accounts/{%O:guid}"

    /// <summary>Replace the user's account and record its new balance, if
    /// any, and read it back, in one database transaction. Fails with
    /// <c>NotFound</c> when the user has no account with the id.</summary>
    let private update
        (queryContext : QueryContextFactory)
        (userId : string)
        (account : Account)
        (observation : BalanceObservation option)
        =
        task {
            let row = AccountCodec.toRow account userId

            use! ctx = queryContext.OpenContextAsync ()
            ctx.BeginTransaction ()

            let! rowsAffected =
                updateTask ctx {
                    for a in main.Accounts do
                        entity row
                        excludeColumn a.Id
                        where (a.Id = row.Id && a.UserId = userId)
                }

            if rowsAffected = 0 then
                return Error (NotFound $"Account %O{account.Id} not found")
            else
                match observation with
                | Some observation ->
                    do!
                        BalanceObservationStore.record
                            ctx
                            userId
                            account.Id
                            observation
                | None -> ()

                let! updated = AccountQuery.tryRead ctx userId account.Id
                ctx.CommitTransaction ()

                return
                    updated
                    |> Result.requireSome (
                        NotFound $"Account %O{account.Id} not found"
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
                let! (req : WriteAccountRequest) = Json.read ctx

                let! account, observation =
                    WriteAccountRequest.validate (clock ()) req id

                do!
                    Constraints.requireOne (
                        AccountQuery.requireNumberIsUnique
                            queryContext
                            userId
                            account
                    )

                let! updated = update queryContext userId account observation

                log.Info (
                    $"Updated account %O{id}",
                    LogProp.prop "accountId" (id.ToString ())
                )

                do! Json.write ctx (AccountResponse.fromDomain updated)
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Update an account"

        op.Description <-
            "Replaces the account's name, number, and term, and records its \
            balance when one is given. A balance on a date that already has \
            one replaces it. Returns the account with its current balance: \
            the latest by as-of date."

        op.Tags <- HashSet [ OpenApiTagReference "Accounts" ]

        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) (clock : Clock) =
        routef Path (handler queryContext clock)
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<WriteAccountRequest>,
                responseBodies = [|
                    ResponseBody typeof<AccountResponse>
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 404)
                    ResponseBody (typeof<ApiError>, statusCode = 409)
                |],
                configureOperation = configureOperation
            )
        )
