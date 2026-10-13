namespace Budgeteur.Feature.Account

module CreateAccount =
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
    open Budgeteur.Domain.Term
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.Clock
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.OpenApi
    open Budgeteur.Shared.RequestLogging

    /// <summary>Payload for creating an account. The id is generated
    /// server-side.</summary>
    type CreateAccountRequest = {
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

        /// <summary>The account's opening balance, or none to leave it
        /// unknown.</summary>
        Balance : BalanceEntryRequest option
    }

    [<Literal>]
    let Path = "/api/accounts"

    /// <summary>Validate the request as of the instant <c>now</c>, which bounds
    /// the balance's as-of date. Returns the account and its opening balance,
    /// if any.</summary>
    let private validate
        (now : DateTimeOffset)
        (req : CreateAccountRequest)
        (id : Guid)
        =
        validation {
            let! account =
                AccountRequest.details id req.Name req.Number req.Term

            and! observation =
                req.Balance
                |> Option.traverseResult (AccountRequest.balance now)

            return account, observation
        }
        |> DomainError.joinValidationErrors

    /// <summary>Insert the account and its balance, if any, and read it back,
    /// in one database transaction.</summary>
    let private insert
        (queryContext : QueryContextFactory)
        (userId : string)
        (account : Account)
        (observation : BalanceObservation option)
        =
        task {
            use! ctx = queryContext.OpenContextAsync ()
            ctx.BeginTransaction ()

            let! _ =
                insertTask ctx {
                    for a in main.Accounts do
                        entity (AccountCodec.toRow account userId)
                }

            match observation with
            | Some observation ->
                do!
                    BalanceObservationStore.record
                        ctx
                        userId
                        account.Id
                        observation
            | None -> ()

            let! created = AccountQuery.tryRead ctx userId account.Id
            ctx.CommitTransaction ()

            return
                created
                |> Result.requireSome (
                    NotFound $"Account %O{account.Id} not found"
                )
        }

    let private handler
        (queryContext : QueryContextFactory)
        (clock : Clock)
        : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                let! (req : CreateAccountRequest) = Json.read ctx

                let! account, observation =
                    validate (clock ()) req (Guid.CreateVersion7 ())

                do!
                    Constraints.requireOne (
                        AccountQuery.requireNumberIsUnique
                            queryContext
                            userId
                            account
                    )

                let! created = insert queryContext userId account observation

                log.Info (
                    $"Created account %O{account.Id}",
                    LogProp.prop "accountId" (account.Id.ToString ())
                )

                ctx.SetStatusCode 201
                do! Json.write ctx (AccountResponse.fromDomain created)
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Create an account"

        op.Description <-
            "Creates an account, recording its balance when one is given, and \
            returns it with status 201."

        op.Tags <- HashSet [ OpenApiTagReference "Accounts" ]

        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) (clock : Clock) =
        route Path (handler queryContext clock)
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<CreateAccountRequest>,
                responseBodies = [|
                    ResponseBody (typeof<AccountResponse>, statusCode = 201)
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 409)
                |],
                configureOperation = configureOperation
            )
        )
