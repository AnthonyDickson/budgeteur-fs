namespace Budgeteur.Shared.Json

/// <summary>HTTP helpers for reading and writing JSON payloads.</summary>
module Json =
    open System.IO
    open System.Text

    open Microsoft.AspNetCore.Http

    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Coders

    let write (ctx : HttpContext) (object : 'T) =
        task {
            ctx.Response.ContentType <- "application/json; charset=utf-8"
            return! ctx.Response.WriteAsync (Encode.toStringAuto object)
        }

    let read (ctx : HttpContext) =
        task {
            use reader = new StreamReader (ctx.Request.Body, Encoding.UTF8)
            let! body = reader.ReadToEndAsync ()
            return Decode.fromStringAuto body |> Result.mapError ValidationFailed
        }
