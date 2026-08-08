namespace Budgeteur.Coders

open System
open Thoth.Json.Net

module Extra =
    let extra = Extra.empty |> Extra.withDecimal |> Extra.withInt64

module Decode =
    let inline cachedDecoder<'T> : Decoder<'T> =
        Decode.Auto.generateDecoderCached<'T> (caseStrategy = CamelCase, extra = Extra.extra)

    let inline fromStringAuto<'T> (json : string) : Result<'T, string> =
        Decode.fromString cachedDecoder<'T> json

module Encode =
    let inline cachedEncoder<'T> : Encoder<'T> =
        Encode.Auto.generateEncoderCached<'T> (caseStrategy = CamelCase, extra = Extra.extra, skipNullField = false)

    let inline toStringAuto<'T> (value : 'T) : string =
        let jsonValue = cachedEncoder<'T> value
        Encode.toString 0 jsonValue
