namespace Budgeteur.Feature.Transaction

open System

/// <summary>A page of a search's matches.</summary>
type SearchResponse = {
    /// <summary>Up to 100 matches, newest first, then by id.</summary>
    Transactions : TransactionResponse list

    /// <summary>Where the next page starts, to send with the same criteria, or
    /// none on the last page.</summary>
    Cursor : string option

    /// <summary>The dates criterion's first day, with a preset resolved, or
    /// none.</summary>
    From : DateOnly option

    /// <summary>The dates criterion's last day, with a preset resolved, or
    /// none.</summary>
    To : DateOnly option
}

module SearchTransactions =
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi

    open Budgeteur.Data.Db
    open Budgeteur.Feature.Transaction
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/transactions/search"

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                let! (req : SearchRequest) = Json.read ctx
                let! search, after = TransactionSearch.validate req

                use! db = queryContext.OpenContextAsync ()

                let! matches, next =
                    TransactionQuery.search db userId search after

                // The criteria are financial data, so only the count is
                // logged.
                log.Info (
                    $"Returned %i{List.length matches} matching transactions",
                    LogProp.prop "count" (List.length matches)
                )

                let transactions =
                    matches
                    |> List.map (fun (transaction, categorisation, account) ->
                        TransactionResponse.fromDomain
                            transaction
                            categorisation
                            account)

                do!
                    Json.write ctx {
                        Transactions = transactions
                        Cursor = Option.map Cursor.toString next
                        From = search.From
                        To = search.To
                    }
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Search transactions"

        op.Description <-
            "Returns a page of the user's transactions that meet every \
            criterion, newest first, and a cursor for the next page. Date \
            presets are resolved from the client's today, and the response \
            carries the resolved days. A POST so the criteria are a typed \
            body; it changes nothing."

        op.Tags <- HashSet [ OpenApiTagReference "Transactions" ]

        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) =
        route Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<SearchRequest>,
                responseBodies = [|
                    ResponseBody typeof<SearchResponse>
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                |],
                configureOperation = configureOperation
            )
        )
