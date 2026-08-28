namespace Budgeteur.Shared.Endpoint


/// <summary>Maps <c>Task&lt;Result&lt;unit, DomainError&gt;&gt;</c> results into HTTP responses
/// suitable for Oxpecker endpoint handlers.</summary>
[<RequireQualifiedAccess>]
module Endpoint =
    open System.Threading.Tasks

    open Microsoft.AspNetCore.Http
    open Microsoft.Data.Sqlite

    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    let private errorTypeName (err : DomainError) =
        match err with
        | ValidationFailed _ -> "ValidationFailed"
        | NotFound _ -> "NotFound"
        | Conflict _ -> "Conflict"
        | Unauthorised -> "Unauthorised"
        | DatabaseError _ -> "DatabaseError"
        | UnhandledException _ -> "UnhandledException"

    let handler (handler_fun : HttpContext -> Task<Result<unit, DomainError>>) : (HttpContext -> Task) =
        fun (ctx : HttpContext) ->
            task {
                let log = RequestLog.fromContext ctx

                let! result =
                    task {
                        try
                            return! handler_fun ctx
                        with
                        | :? SqliteException as exn when exn.SqliteErrorCode = 19 ->
                            log.Warn (
                                $"Unhandled constraint violation: {exn.Message}",
                                LogProp.prop "exception" (exn.ToString ())
                            )

                            return Error (Conflict exn)
                        | :? SqliteException as exn -> return Error (DatabaseError exn)
                        | exn -> return Error (UnhandledException exn)
                    }

                match result with
                | Ok () -> ()
                | Error (ValidationFailed err) ->
                    log.Warn (
                        $"Validation failed: {err}",
                        LogProp.prop "errorType" "ValidationFailed",
                        LogProp.prop "error" err
                    )

                    ctx.Response.StatusCode <- 400

                    return!
                        Json.write ctx {
                            Error = "Validation Error"
                            Details = err
                            StatusCode = Some 400
                            RequestId = ctx.TraceIdentifier
                        }
                | Error Unauthorised ->
                    log.Error "Got a request where the user claims were not defined"
                    ctx.Response.StatusCode <- 401

                    return!
                        Json.write ctx {
                            Error = "Unauthorized"
                            Details = "Did not find claims in the request data"
                            StatusCode = Some 401
                            RequestId = ctx.TraceIdentifier
                        }
                | Error (NotFound err) ->
                    log.Warn ($"Not found: {err}", LogProp.prop "errorType" "NotFound", LogProp.prop "error" err)
                    ctx.Response.StatusCode <- 404

                    return!
                        Json.write ctx {
                            Error = "Not Found"
                            Details = err
                            StatusCode = Some 404
                            RequestId = ctx.TraceIdentifier
                        }
                | Error (Conflict exn) ->
                    log.Warn (
                        $"Conflict: {exn}",
                        LogProp.prop "errorType" "Conflict",
                        LogProp.prop "exception" (exn.ToString ())
                    )

                    ctx.Response.StatusCode <- 409

                    return!
                        Json.write ctx {
                            Error = "Conflict"
                            Details =
                                "The request could not be completed due to unhandled database constraint violations."
                            StatusCode = Some 409
                            RequestId = ctx.TraceIdentifier
                        }
                | Error (DatabaseError exn | UnhandledException exn as err) ->
                    let errorType = errorTypeName err

                    log.Error (
                        exn.ToString (),
                        LogProp.prop "errorType" errorType,
                        LogProp.prop "exception" (exn.ToString ())
                    )

                    ctx.Response.StatusCode <- 500

                    return!
                        Json.write ctx {
                            Error = "Internal Server Error"
                            Details = "An unexpected error occurred"
                            StatusCode = Some 500
                            RequestId = ctx.TraceIdentifier
                        }
            }
