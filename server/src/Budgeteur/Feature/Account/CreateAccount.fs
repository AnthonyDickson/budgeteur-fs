namespace Budgeteur.Feature.Account

module CreateAccount =
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
    let Path = "/api/accounts"

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
                let! (req : WriteAccountRequest) = Json.read ctx

                let! account, observation =
                    WriteAccountRequest.validate
                        (clock ())
                        req
                        (Guid.CreateVersion7 ())

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
                requestBody = RequestBody typeof<WriteAccountRequest>,
                responseBodies = [|
                    ResponseBody (typeof<AccountResponse>, statusCode = 201)
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 409)
                |],
                configureOperation = configureOperation
            )
        )
