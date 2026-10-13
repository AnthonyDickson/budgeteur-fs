namespace Budgeteur.Feature.Account

module UpdateAccount =
    open System
    open System.Collections.Generic
    open System.ComponentModel.DataAnnotations
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi
    open SqlHydra.Query

    open Budgeteur.Data
    open Budgeteur.Data.Db
    open Budgeteur.Domain.Account
    open Budgeteur.Domain.CloseDate
    open Budgeteur.Domain.Term
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.Clock
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.OpenApi
    open Budgeteur.Shared.RequestLogging

    /// <summary>Payload for updating an account's details. Balances are
    /// recorded separately.</summary>
    type UpdateAccountRequest = {
        /// <summary>The user's alias for the account.</summary>
        [<MinLength(1)>]
        [<MaxLength(AccountName.MaxLength)>]
        Name : string

        /// <summary>The number statements identify the account by: an NZ bank
        /// account number or a masked card number. None, or blank, for an
        /// account without one.</summary>
        Number : string option

        /// <summary>Whether the account is current or non-current.</summary>
        [<SchemaHint.Enum(typeof<Term>)>]
        Term : string

        /// <summary>The date the account was closed, or none to keep it open.
        /// At most one day after the server's UTC date.</summary>
        ClosedOn : DateOnly option
    }

    [<Literal>]
    let Path = "/api/accounts/{%O:guid}"

    /// <summary>Replace the user's account and read it back, in one database
    /// transaction. Fails with <c>NotFound</c> when the user has no account
    /// with the id.</summary>
    let private update
        (queryContext : QueryContextFactory)
        (userId : string)
        (account : Account)
        =
        task {
            let row = AccountCodec.toRow account userId

            use! ctx = queryContext.OpenContextAsync ()
            ctx.BeginTransaction ()

            let! _ =
                updateTask ctx {
                    for a in main.Accounts do
                        entity row
                        excludeColumn a.Id
                        where (a.Id = row.Id && a.UserId = userId)
                }

            let! updated = AccountQuery.tryRead ctx userId account.Id
            ctx.CommitTransaction ()

            return
                updated
                |> Result.requireSome (
                    NotFound $"Account %O{account.Id} not found"
                )
        }

    /// <summary>Validate the request as of the instant <c>now</c>, which bounds
    /// the close date.</summary>
    let private validate
        (now : DateTimeOffset)
        (req : UpdateAccountRequest)
        (id : Guid)
        =
        validation {
            let! account =
                AccountRequest.details id req.Name req.Number req.Term

            and! closedOn =
                req.ClosedOn |> Option.traverseResult (CloseDate.validate now)

            return { account with ClosedOn = closedOn }
        }
        |> DomainError.joinValidationErrors

    let private handler
        (queryContext : QueryContextFactory)
        (clock : Clock)
        (id : Guid)
        : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                let! (req : UpdateAccountRequest) = Json.read ctx

                let! account = validate (clock ()) req id

                do!
                    Constraints.requireOne (
                        AccountQuery.requireNumberIsUnique
                            queryContext
                            userId
                            account
                    )

                let! updated = update queryContext userId account

                log.Info (
                    $"Updated account %O{id}",
                    LogProp.prop "accountId" (id.ToString ())
                )

                do! Json.write ctx (AccountResponse.fromDomain updated)
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Update an account"

        op.Description <-
            "Replaces the account's name, number, term, and close date, \
            leaving its balance history as it is. Returns the account with its \
            current balance."

        op.Tags <- HashSet [ OpenApiTagReference "Accounts" ]

        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) (clock : Clock) =
        routef Path (handler queryContext clock)
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<UpdateAccountRequest>,
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
