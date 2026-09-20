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
    open Budgeteur.Domain.BalanceSheet
    open Budgeteur.Shared.OpenApi
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/balance-sheet"

    type BalanceSheetResponse = {
        /// <summary>The date the balances are accurate as of.</summary>
        StatementDate : DateTime

        /// <summary>Every asset and liability currently being tracked.</summary>
        Items : BalanceSheetItemResponse list

        /// <summary>Total value of assets expected to be realised within the current period.</summary>
        [<SchemaHint.Decimal(NonNegative = true)>]
        TotalCurrentAssets : decimal

        /// <summary>Total value of liabilities expected to be settled within the current period.</summary>
        [<SchemaHint.Decimal(NonNegative = true)>]
        TotalCurrentLiabilities : decimal

        /// <summary>Total value of assets **not** expected to be realised within the current period.</summary>
        [<SchemaHint.Decimal(NonNegative = true)>]
        TotalNonCurrentAssets : decimal

        /// <summary>Total value of liabilities **not** expected to be settled within the current period.</summary>
        [<SchemaHint.Decimal(NonNegative = true)>]
        TotalNonCurrentLiabilities : decimal

        /// <summary>Total value of everything owned, both current and non-current.</summary>
        [<SchemaHint.Decimal(NonNegative = true)>]
        TotalAssets : decimal

        /// <summary>Total value of everything owed, both current and non-current.</summary>
        [<SchemaHint.Decimal(NonNegative = true)>]
        TotalLiabilities : decimal

        /// <summary>Total assets minus total liabilities.</summary>
        NetWorth : decimal

        /// <summary>
        /// Current assets minus current liabilities: the near-term position. Unlike net worth it
        /// excludes non-current debt, so it stays sensitive to near-term decisions.
        /// </summary>
        WorkingCapital : decimal
    }

    module BalanceSheetResponse =
        let fromDomain (sheet : BalanceSheet) : BalanceSheetResponse = {
            StatementDate = sheet.StatementDate
            Items = sheet.Items |> List.map BalanceSheetItemResponse.fromDomain
            TotalCurrentAssets = BalanceSheet.totalCurrentAssets sheet
            TotalCurrentLiabilities = BalanceSheet.totalCurrentLiabilities sheet
            TotalNonCurrentAssets = BalanceSheet.totalNonCurrentAssets sheet
            TotalNonCurrentLiabilities = BalanceSheet.totalNonCurrentLiabilities sheet
            TotalAssets = BalanceSheet.totalAssets sheet
            TotalLiabilities = BalanceSheet.totalLiabilities sheet
            NetWorth = BalanceSheet.netWorth sheet
            WorkingCapital = BalanceSheet.workingCapital sheet
        }

    /// <summary> Get the user's balance sheet if it exists.</summary>
    let tryFindBalanceSheet (queryContext : QueryContextFactory) (userId : string) : Task<BalanceSheet option> =
        task {
            let! sheet =
                selectTask queryContext {
                    for b in main.BalanceSheets do
                        where (b.UserId = userId)
                        tryHead
                }

            and! items =
                selectTask queryContext {
                    for item in main.BalanceSheetItems do
                        where (item.UserId = userId)
                }

            let items = Seq.map BalanceSheetItemCodec.fromRow items |> List.ofSeq

            return Option.map (fun sheet -> BalanceSheetCodec.fromRow sheet items) sheet
        }

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                let! sheet = tryFindBalanceSheet queryContext userId

                match sheet with
                | Some sheet ->
                    log.Info "Returned balance sheet"
                    do! Json.write ctx (BalanceSheetResponse.fromDomain sheet)
                | None ->
                    log.Info "Returned temporary balance sheet, could not find existing balance sheet"

                    let sheet : BalanceSheet = {
                        StatementDate = DateTime.UtcNow
                        Items = []
                    }

                    do! Json.write ctx (BalanceSheetResponse.fromDomain sheet)
            })

    let endpoint (queryContext : QueryContextFactory) =
        route Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                responseBodies = [|
                    ResponseBody typeof<BalanceSheetResponse>
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                |],
                configureOperation =
                    fun op _ _ ->
                        op.Summary <- "Get balance sheet"
                        op.Description <- "Returns the user's balance sheet."
                        op.Tags <- HashSet [ OpenApiTagReference "Balance Sheets" ]
                        Task.CompletedTask
            )
        )
