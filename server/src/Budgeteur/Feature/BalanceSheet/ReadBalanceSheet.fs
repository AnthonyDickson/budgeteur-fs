namespace Budgeteur.Feature.BalanceSheet

module ReadBalanceSheet =
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
    open Budgeteur.Domain.BalanceSheet
    open Budgeteur.Domain.BalanceSheetItem
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.OpenApi
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/balance-sheet"

    /// <summary>The user's balance sheet. It carries no statement date: the
    /// client draws it for its own today, and each line has an as-of date.
    /// Closed lines are listed apart and left out of the totals.</summary>
    type BalanceSheetResponse = {
        /// <summary>Every asset and liability that is not an account.</summary>
        Items : BalanceSheetItemResponse list

        /// <summary>Every account with a known balance, as a line.</summary>
        Accounts : AccountLineResponse list

        /// <summary>Accounts whose balance is unknown, left out of the
        /// totals.</summary>
        UnknownBalances : UnknownBalanceResponse list

        /// <summary>Items that were sold or repaid, left out of the
        /// sheet.</summary>
        ClosedItems : BalanceSheetItemResponse list

        /// <summary>Accounts that were closed, left out of the sheet.</summary>
        ClosedAccounts : ClosedAccountResponse list

        /// <summary>Total value of assets expected to be realised within the
        /// current period.</summary>
        [<SchemaHint.Decimal(NonNegative = true)>]
        TotalCurrentAssets : decimal

        /// <summary>Total value of liabilities expected to be settled within
        /// the current period.</summary>
        [<SchemaHint.Decimal(NonNegative = true)>]
        TotalCurrentLiabilities : decimal

        /// <summary>Total value of assets **not** expected to be realised
        /// within the current period.</summary>
        [<SchemaHint.Decimal(NonNegative = true)>]
        TotalNonCurrentAssets : decimal

        /// <summary>Total value of liabilities **not** expected to be settled
        /// within the current period.</summary>
        [<SchemaHint.Decimal(NonNegative = true)>]
        TotalNonCurrentLiabilities : decimal

        /// <summary>Total value of everything owned, both current and
        /// non-current.</summary>
        [<SchemaHint.Decimal(NonNegative = true)>]
        TotalAssets : decimal

        /// <summary>Total value of everything owed, both current and
        /// non-current.</summary>
        [<SchemaHint.Decimal(NonNegative = true)>]
        TotalLiabilities : decimal

        /// <summary>Total assets minus total liabilities.</summary>
        NetWorth : decimal

        /// <summary>
        /// Current assets minus current liabilities: the near-term position.
        /// Unlike net worth it excludes non-current debt, so it stays sensitive
        /// to near-term decisions.
        /// </summary>
        WorkingCapital : decimal
    }

    module BalanceSheetResponse =
        let fromDomain
            (sheet : BalanceSheet)
            (closedItems : ItemValue list)
            (closedAccounts : Account list)
            (transactionsAfterClose : (Guid * DateOnly) list)
            : BalanceSheetResponse =
            let datesAfterClose (account : Account) =
                transactionsAfterClose
                |> List.filter (fun (accountId, _) -> accountId = account.Id)
                |> List.map snd

            {
                Items =
                    sheet.Items |> List.map BalanceSheetItemResponse.fromDomain
                Accounts =
                    sheet.Accounts |> List.choose AccountLineResponse.fromDomain
                UnknownBalances =
                    BalanceSheet.unknownBalances sheet
                    |> List.map UnknownBalanceResponse.fromDomain
                ClosedItems =
                    closedItems |> List.map BalanceSheetItemResponse.fromDomain
                ClosedAccounts =
                    closedAccounts
                    |> List.choose (fun account ->
                        ClosedAccountResponse.fromDomain
                            (datesAfterClose account)
                            account)
                TotalCurrentAssets = BalanceSheet.totalCurrentAssets sheet
                TotalCurrentLiabilities =
                    BalanceSheet.totalCurrentLiabilities sheet
                TotalNonCurrentAssets = BalanceSheet.totalNonCurrentAssets sheet
                TotalNonCurrentLiabilities =
                    BalanceSheet.totalNonCurrentLiabilities sheet
                TotalAssets = BalanceSheet.totalAssets sheet
                TotalLiabilities = BalanceSheet.totalLiabilities sheet
                NetWorth = BalanceSheet.netWorth sheet
                WorkingCapital = BalanceSheet.workingCapital sheet
            }

    /// <summary>The user's balance sheet: every open item and account they
    /// track, and apart from it the closed ones. A user with neither has an
    /// empty sheet. A close date cannot be in the future, so every closed line
    /// is left out of the current sheet.</summary>
    let private readBalanceSheet
        (queryContext : QueryContextFactory)
        (userId : string)
        : Task<BalanceSheet * ItemValue list * Account list> =
        task {
            use! db = queryContext.OpenContextAsync ()
            let! items = ItemQuery.readAll db userId

            let! accounts =
                selectTask db {
                    for a in main.Accounts do
                        leftJoin' c in main.LeftJoined.CurrentBalances
                        on' (Some a.Id = c.AccountId)

                        where (a.UserId = userId)
                        orderBy a.Name
                        select (a, c)
                }

            let closedItems, openItems =
                items |> List.partition (fun item -> item.Item.ClosedOn.IsSome)

            let closedAccounts, openAccounts =
                accounts
                |> Seq.map AccountBalanceCodec.fromRow
                |> List.ofSeq
                |> List.partition (fun account ->
                    account.Account.ClosedOn.IsSome)

            let sheet = {
                Items = openItems
                Accounts = openAccounts
            }

            return sheet, closedItems, closedAccounts |> List.map _.Account
        }

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx

                let! sheet, closedItems, closedAccounts =
                    readBalanceSheet queryContext userId

                and! transactionsAfterClose =
                    TransactionsAfterCloseQuery.read queryContext userId

                log.Info "Returned balance sheet"

                do!
                    Json.write
                        ctx
                        (BalanceSheetResponse.fromDomain
                            sheet
                            closedItems
                            closedAccounts
                            transactionsAfterClose)
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Get balance sheet"
        op.Description <- "Returns the user's balance sheet."

        op.Tags <- HashSet [ OpenApiTagReference "Balance Sheets" ]

        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) =
        route Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                responseBodies = [|
                    ResponseBody typeof<BalanceSheetResponse>
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                |],
                configureOperation = configureOperation
            )
        )
