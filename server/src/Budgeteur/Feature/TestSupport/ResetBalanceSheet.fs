namespace Budgeteur.Feature.TestSupport

/// Dev-only endpoint used by the E2E suite to clear the current user's balance
/// sheet data between tests (and retries). It is registered only in the
/// Development environment (see `Program.fs`), so it cannot be reached against
/// real data.
module ResetBalanceSheet =
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Oxpecker
    open SqlHydra.Query

    open Budgeteur.Data.Db
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/test/balance-sheet"

    let private deleteAll (queryContext : QueryContextFactory) (userId : string) : Task<unit> =
        task {
            // Items are not referenced by the sheet, but delete them first so the
            // reset leaves no orphans if the sheet is ever cascaded.
            let! _ =
                deleteTask queryContext {
                    for item in main.BalanceSheetItems do
                        where (item.UserId = userId)
                }

            let! _ =
                deleteTask queryContext {
                    for sheet in main.BalanceSheets do
                        where (sheet.UserId = userId)
                }

            return ()
        }

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                do! deleteAll queryContext userId
                log.Info "Reset balance sheet data for test user"
                ctx.SetStatusCode 204
                return ()
            })

    let endpoint (queryContext : QueryContextFactory) = route Path (handler queryContext)
