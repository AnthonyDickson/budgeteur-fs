namespace Budgeteur.Feature.TestSupport

/// Dev-only endpoint used by the E2E suite to clear the current user's tagging
/// data between tests (and retries). It is registered only in the Development
/// environment (see `Program.fs`), so it cannot be reached against real data.
module ResetTagging =
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Oxpecker
    open SqlHydra.Query

    open Budgeteur.Data.Db
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/test/tagging"

    let private deleteAll (queryContext : QueryContextFactory) (userId : string) : Task<unit> =
        task {

            // Rules reference tags with ON DELETE CASCADE, but delete them
            // first so the reset does not depend on the FK pragma being on.
            let! _ =
                deleteTask queryContext {
                    for r in main.Rules do
                        where (r.UserId = userId)
                }

            let! _ =
                deleteTask queryContext {
                    for t in main.Tags do
                        where (t.UserId = userId)
                }

            return ()
        }

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                do! deleteAll queryContext userId
                log.Info "Reset tagging data for test user"
                ctx.SetStatusCode 204
                return ()
            })

    let endpoint (queryContext : QueryContextFactory) = route Path (handler queryContext)
