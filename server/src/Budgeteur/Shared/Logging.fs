namespace Budgeteur.Shared.Logging

/// <summary>The global Serilog pipeline: startup, framework, and unhandled
/// exception logs. Request-scoped logs are in <c>RequestLogging</c>.</summary>
[<RequireQualifiedAccess>]
module Logging =
    open System

    open Microsoft.Extensions.Hosting
    open Serilog
    open Serilog.Events
    open Serilog.Formatting.Compact

    open Budgeteur.Shared.Config

    /// <summary>Log compact JSON to the console, and to a file when one is
    /// configured. <c>statusPath</c> is the health check endpoint, whose
    /// successful probes are dropped.</summary>
    let configure
        (statusPath : string)
        (loggingOptions : LoggingConfig)
        (_ : HostBuilderContext)
        (config : LoggerConfiguration)
        =
        let filePath =
            loggingOptions.FilePath
            |> Option.ofObj
            |> Option.filter (not << String.IsNullOrWhiteSpace)

        config.MinimumLevel.Information () |> ignore

        // Filter out healthcheck noise for the status endpoint. Framework
        // per-request logs (Microsoft.AspNetCore.Hosting.Diagnostics) carry no
        // status code, so they are dropped whenever the path matches. The app's
        // own buffered request-log summary does carry the status code, so only
        // successful probes are dropped; failures (503) stay visible.
        config.Filter.ByExcluding (fun (e : LogEvent) ->
            let prop name =
                match e.Properties.TryGetValue name with
                | true, (:? ScalarValue as sv) -> string sv.Value
                | _ -> ""

            let source = prop "SourceContext"
            let requestPath = prop "RequestPath"

            let statusCode =
                match e.Properties.TryGetValue "StatusCode" with
                | true, (:? ScalarValue as sv) ->
                    match Int32.TryParse (string sv.Value) with
                    | true, code -> code
                    | _ -> 0
                | _ -> 0

            let isStatusProbe = requestPath.StartsWith statusPath

            let isFrameworkLog =
                source.StartsWith "Microsoft.AspNetCore"
                || source.StartsWith "Microsoft.Hosting"

            isStatusProbe && (isFrameworkLog || statusCode < 400))
        |> ignore

        config.WriteTo.Console (RenderedCompactJsonFormatter ()) |> ignore

        match filePath with
        | Some path ->
            config.WriteTo.File (RenderedCompactJsonFormatter (), path)
            |> ignore
        | None -> ()
