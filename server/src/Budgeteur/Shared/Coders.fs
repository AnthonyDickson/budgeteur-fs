namespace Budgeteur.Shared.Coders

open System
open System.Globalization
open Thoth.Json.Net

module Extra =
    module DateOnly =
        let encode (date : DateOnly) =
            // Format as ISO-8601, e.g. 2026-08-09
            Encode.string (date.ToString "O")

        /// Parse an ISO-8601 date (e.g. 2026-08-09) regardless of the server's
        /// culture.
        let tryParse (dateString : string) =
            match
                DateOnly.TryParseExact (
                    dateString,
                    "yyyy-MM-dd",
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.None
                )
            with
            | true, date -> Some date
            | false, _ -> None

        let decoder : Decoder<DateOnly> =
            Decode.string
            |> Decode.andThen (fun dateString ->
                match tryParse dateString with
                | Some date -> Decode.succeed date
                | None ->
                    Decode.fail
                        $"Expected a date in the ISO-8601 format, got \
                        {dateString}")

    let extra =
        Extra.empty
        |> Extra.withDecimal
        |> Extra.withInt64
        |> Extra.withCustom DateOnly.encode DateOnly.decoder

module Decode =
    let inline cachedDecoder<'T> : Decoder<'T> =
        Decode.Auto.generateDecoderCached<'T>(
            caseStrategy = CamelCase,
            extra = Extra.extra
        )

    let inline fromStringAuto<'T> (json : string) : Result<'T, string> =
        Decode.fromString cachedDecoder<'T> json

module Encode =
    let inline cachedEncoder<'T> : Encoder<'T> =
        Encode.Auto.generateEncoderCached<'T>(
            caseStrategy = CamelCase,
            extra = Extra.extra,
            skipNullField = false
        )

    let inline toStringAuto<'T> (value : 'T) : string =
        let jsonValue = cachedEncoder<'T> value
        Encode.toString 0 jsonValue
