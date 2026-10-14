namespace Budgeteur.Feature.Account

module CloseAccount =
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
    open Budgeteur.Domain.CloseDate
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.Clock
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    /// <summary>Payload for closing an account.</summary>
    type CloseAccountRequest = {
        /// <summary>The date the account was closed. At most one day after
        /// the server's UTC date. Replaces any earlier close date.</summary>
        ClosedOn : DateOnly
    }

    [<Literal>]
    let Path = "/api/accounts/{%O:guid}/close-date"

    /// <summary>Set the user's account's close date and read the account back,
    /// in one database transaction. Fails with <c>NotFound</c> when the user
    /// has no account with the id.</summary>
    let private close
        (queryContext : QueryContextFactory)
        (userId : string)
        (accountId : Guid)
        (closedOn : DateOnly)
        =
        task {
            use! ctx = queryContext.OpenContextAsync ()
            ctx.BeginTransaction ()
            let closedOn = Some closedOn

            let! _ =
                updateTask ctx {
                    for a in main.Accounts do
                        set a.ClosedOn closedOn
                        where (a.Id = accountId && a.UserId = userId)
                }

            let! closed = AccountQuery.tryRead ctx userId accountId
            ctx.CommitTransaction ()

            return
                closed
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
                let! (req : CloseAccountRequest) = Json.read ctx
                let! closedOn = CloseDate.validate (clock ()) req.ClosedOn
                let! account = close queryContext userId id closedOn

                log.Info (
                    $"Closed account %O{id} on %O{closedOn}",
                    LogProp.prop "accountId" (id.ToString ())
                )

                do! Json.write ctx (AccountResponse.fromDomain account)
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Close an account"

        op.Description <-
            "Sets the date the account was closed. Balance sheets drawn on or \
            after it leave the account out; earlier ones keep it. Returns the \
            account with its current balance."

        op.Tags <- HashSet [ OpenApiTagReference "Accounts" ]

        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) (clock : Clock) =
        routef Path (handler queryContext clock)
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<CloseAccountRequest>,
                responseBodies = [|
                    ResponseBody typeof<AccountResponse>
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 404)
                |],
                configureOperation = configureOperation
            )
        )
