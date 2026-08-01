namespace Budgeteur.Server.Endpoint

open System.Threading.Tasks
open Microsoft.AspNetCore.Http

open Budgeteur.Server.ApiError
open Budgeteur.Server.DomainError
open Budgeteur.Server.RequestLogging
open Budgeteur.Server.Json

/// <summary>Maps <c>Task&lt;Result&lt;unit, DomainError&gt;&gt;</c> results into HTTP responses
/// suitable for Oxpecker endpoint handlers.</summary>
[<RequireQualifiedAccess>]
module Endpoint =
    let private errorTypeName (err : DomainError) =
        match err with
        | ValidationFailed _ -> "ValidationFailed"
        | NotFound _ -> "NotFound"
        | Conflict _ -> "Conflict"
        | UserNotFound -> "UserNotFound"
        | DatabaseError _ -> "DatabaseError"
        | UnhandledException _ -> "UnhandledException"

    let run (ctx : HttpContext) (body : Task<Result<unit, DomainError>>) : Task =
        task {
            let log = RequestLog.fromContext ctx

            match! body with
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
            | Error (Conflict err) ->
                log.Warn ($"Conflict: {err}", LogProp.prop "errorType" "Conflict", LogProp.prop "error" err)
                ctx.Response.StatusCode <- 409

                return!
                    Json.write ctx {
                        Error = "Conflict"
                        Details = err
                        StatusCode = Some 409
                        RequestId = ctx.TraceIdentifier
                    }
            | Error UserNotFound ->
                log.Error "Got a request where the user claims were not defined"
                ctx.Response.StatusCode <- 401

                return!
                    Json.write ctx {
                        Error = "Unauthorized"
                        Details = "Did not find claims in the request data"
                        StatusCode = Some 401
                        RequestId = ctx.TraceIdentifier
                    }
            | Error (DatabaseError (msg, exOpt) | UnhandledException (msg, exOpt) as err) ->
                let fullMsg =
                    match exOpt with
                    | Some ex -> $"{msg}\n{ex}"
                    | None -> msg

                let errorType = errorTypeName err

                log.Error (
                    fullMsg,
                    LogProp.prop "errorType" errorType,
                    LogProp.prop "error" msg,
                    LogProp.prop "exception" (exOpt |> Option.map string |> Option.defaultValue "")
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

    let handler (body : HttpContext -> Task<Result<unit, DomainError>>) =
        fun (ctx : HttpContext) -> run ctx (body ctx)
