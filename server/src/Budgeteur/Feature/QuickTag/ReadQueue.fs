namespace Budgeteur.Feature.QuickTag

open System

/// <summary>A transaction waiting for a tag.</summary>
type QueuedTransactionResponse = {
    Id : Guid

    /// <summary>A debit (negative) or credit (positive). Serialised as a
    /// string.</summary>
    Amount : decimal

    Description : string

    /// <summary>The calendar date the transaction occurred.</summary>
    Date : DateOnly

    /// <summary>The name of the transaction's account, if it has one.</summary>
    AccountName : string option
}

/// <summary>A batch of the quick tagging queue.</summary>
type QueueResponse = {
    /// <summary>Up to 50 of the user's untagged transactions, newest first.
    /// Tagging, dismissing, or marking them as transfers removes them from the
    /// queue, so fetching again returns the next batch.</summary>
    Transactions : QueuedTransactionResponse list

    /// <summary>How many transactions the whole queue holds.</summary>
    Total : int
}

module ReadQueue =
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
    open Budgeteur.Domain.Transaction
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/quick-tag"

    [<Literal>]
    let BatchSize = 50

    /// <summary>The first batch of the user's queue: transactions without a
    /// categorisation, which excludes dismissed ones and transfers, newest
    /// first. See decision 2 in docs/quick-tagging.md.</summary>
    let private readBatch
        (queryContext : QueryContextFactory)
        (userId : string)
        =
        task {
            let! rows =
                selectTask queryContext {
                    for t in main.Transactions do
                        leftJoin a in main.LeftJoined.Categorisations
                                          on
                                          (t.Id = a.TransactionId)

                        leftJoin' account in main.LeftJoined.Accounts
                        on' (t.AccountId = account.Id)

                        where (t.UserId = userId && isNullValue a.TransactionId)

                        orderByDescending t.Date
                        thenByDescending t.Id
                        take BatchSize
                        select (t, account.Name)
                }

            return
                rows
                |> Seq.map (fun (row, accountName) ->
                    let transaction = TransactionCodec.fromRow row

                    {
                        Id = transaction.Id
                        Amount = Money.value transaction.Amount
                        Description =
                            TransactionDescription.value
                                transaction.Description
                        Date = transaction.Date
                        AccountName = accountName
                    })
                |> List.ofSeq
        }

    /// <summary>How many transactions the user's whole queue holds.</summary>
    let private readTotal
        (queryContext : QueryContextFactory)
        (userId : string)
        =
        selectTask queryContext {
            for t in main.Transactions do
                leftJoin a in main.LeftJoined.Categorisations
                                  on
                                  (t.Id = a.TransactionId)

                where (t.UserId = userId && isNullValue a.TransactionId)

                count
        }

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx

                let! transactions, total =
                    task {
                        let! transactions = readBatch queryContext userId
                        and! total = readTotal queryContext userId
                        return transactions, total
                    }

                log.Info (
                    $"Returned %i{List.length transactions} of %i{total} \
                    queued transactions",
                    LogProp.prop "total" total
                )

                do!
                    Json.write ctx {
                        Transactions = transactions
                        Total = total
                    }
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Read the quick tagging queue"

        op.Description <-
            "Returns the first batch of the user's untagged transactions, \
            newest first, and how many the queue holds. Transfers have a \
            categorisation, so they are not in the queue."

        op.Tags <- HashSet [ OpenApiTagReference "Quick tagging" ]

        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) =
        route Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                responseBodies = [|
                    ResponseBody typeof<QueueResponse>
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                |],
                configureOperation = configureOperation
            )
        )
