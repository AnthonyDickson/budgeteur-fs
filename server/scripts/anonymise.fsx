#!/usr/bin/env -S dotnet fsi

// Anonymise a raw bank export into a test fixture. See decision 14 in
// docs/csv-import.md.
//
// Usage: dotnet fsi anonymise.fsx <input.csv> <output.csv> <key file>
//
// The script works by column name, so it handles formats the app does not
// know yet:
// - account and card numbers become fake ones, consistently across files, so
//   transfer pairs still match;
// - free-text columns are replaced with words from fixed lists, chosen by a
//   keyed hash of the original value, so a recurring merchant stays recurring;
// - every other column (dates, amounts, balances, types, ids) is kept, so
//   running balances still add up.
//
// The hash is an HMAC keyed with the contents of the key file, which is
// created with random bytes when missing. A plain hash of an account number
// could be reversed by trying every number. Keep the key with the raw exports:
// the same key gives the same replacements on every run.

open System
open System.IO
open System.Security.Cryptography
open System.Text
open System.Text.RegularExpressions

let input, output, keyFile =
    match fsi.CommandLineArgs |> Array.tail with
    | [| input; output; keyFile |] -> input, output, keyFile
    | _ ->
        eprintfn "Usage: dotnet fsi anonymise.fsx <input.csv> <output.csv> <key file>"
        exit 2

let key =
    if not (File.Exists keyFile) then
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath keyFile))
        |> ignore

        File.WriteAllBytes(keyFile, RandomNumberGenerator.GetBytes 32)
        eprintfn $"Created a new key in {keyFile}"

    File.ReadAllBytes keyFile

let hash (purpose: string) (value: string) =
    HMACSHA256.HashData(key, Encoding.UTF8.GetBytes($"{purpose}\n{value}"))

// ── Free text ───────────────────────────────────────────────────────────────

// Lower-cased header names of the columns that hold free text.
let freeTextColumns =
    set
        [
            "description"
            "particulars"
            "code"
            "reference"
            "payee"
            "memo"
            "other party name"
            "other party particulars"
            "other party code"
            "other party reference"
        ]

let adjectives =
    [|
        "AMBER"
        "BRIGHT"
        "CEDAR"
        "CORAL"
        "CRIMSON"
        "DAWN"
        "EASTERN"
        "EMBER"
        "FERN"
        "GOLDEN"
        "GRAND"
        "HARBOUR"
        "HIGH"
        "IRON"
        "JADE"
        "KIWI"
        "LUNAR"
        "MAPLE"
        "NORTHERN"
        "OCEAN"
        "PINE"
        "QUIET"
        "RIVER"
        "SILVER"
        "SOUTHERN"
        "STONE"
        "SUNNY"
        "TIDAL"
        "UPPER"
        "VALLEY"
        "WESTERN"
        "WILLOW"
    |]

let nouns =
    [|
        "BAKERY"
        "BOOKS"
        "BREWERY"
        "BUTCHERY"
        "CAFE"
        "CINEMA"
        "CYCLES"
        "DAIRY"
        "DELI"
        "ELECTRICAL"
        "FITNESS"
        "FLORIST"
        "FUEL"
        "GARDENS"
        "GROCER"
        "HARDWARE"
        "KITCHEN"
        "LAUNDRY"
        "MARKET"
        "MOTORS"
        "MUSIC"
        "NOODLES"
        "OPTOMETRY"
        "PHARMACY"
        "PIZZA"
        "POWER"
        "SUSHI"
        "TAKEAWAYS"
        "TELECOM"
        "TRAVEL"
        "VET"
        "WINES"
    |]

let places =
    [|
        "ASHBURTON"
        "BLENHEIM"
        "CAMBRIDGE"
        "DUNEDIN"
        "FEILDING"
        "GISBORNE"
        "GREYMOUTH"
        "HAMILTON"
        "HASTINGS"
        "INVERCARGILL"
        "KAIKOURA"
        "LEVIN"
        "MASTERTON"
        "MOTUEKA"
        "NAPIER"
        "NELSON"
        "OAMARU"
        "PICTON"
        "QUEENSTOWN"
        "RAGLAN"
        "ROTORUA"
        "TAUPO"
        "TAURANGA"
        "TEMUKA"
        "THAMES"
        "TIMARU"
        "TOKOROA"
        "TWIZEL"
        "WAIHI"
        "WANAKA"
        "WHAKATANE"
        "WHANGAREI"
    |]

let replaceText (value: string) =
    if String.IsNullOrWhiteSpace value then
        value
    else
        let bytes = hash "text" (value.Trim())
        let pick (words: string array) (index: int) = words[int bytes[index] % words.Length]
        $"{pick adjectives 0} {pick nouns 1} {pick places 2}"

// ── Account and card numbers ────────────────────────────────────────────────

let bankAccount =
    Regex "\\b([0-9]{2})([- ])([0-9]{4})([- ])([0-9]{1,7})([- ])([0-9]{2,3})\\b"

let maskedCard = Regex "\\b[0-9Xx*]{4}(?:[- ][0-9Xx*]{4,6}){2,3}\\b"

let fakeDigits (bytes: byte array) (count: int) =
    String(Array.init count (fun index -> char (int '0' + int bytes[index] % 10)))

// The bank code and suffix are kept: the bank decides the export format, and
// accounts of one customer share the rest of the number, which the fake keeps
// shared. The account part is always written with seven digits, so every
// print of one account maps to one fake.
let replaceBankAccount (m: Match) =
    let bank = m.Groups[1].Value
    let branchAndAccount = m.Groups[3].Value + "-" + m.Groups[5].Value.PadLeft(7, '0')
    let bytes = hash "account" $"{bank}-{branchAndAccount}"
    let fake = fakeDigits bytes 11

    String.concat
        ""
        [
            bank
            m.Groups[2].Value
            fake.Substring(0, 4)
            m.Groups[4].Value
            fake.Substring(4, 7)
            m.Groups[6].Value
            m.Groups[7].Value
        ]

// Masked digits stay masked; visible digits become fake ones.
let replaceCard (m: Match) =
    if not (m.Value |> Seq.exists (fun char -> char = 'X' || char = 'x' || char = '*')) then
        m.Value
    else
        let digits = fakeDigits (hash "card" m.Value) 32

        m.Value
        |> Seq.mapi (fun index char -> if Char.IsDigit char then digits[index] else char)
        |> Seq.toArray
        |> String

let replaceNumbers (text: string) =
    let text = bankAccount.Replace(text, MatchEvaluator replaceBankAccount)
    maskedCard.Replace(text, MatchEvaluator replaceCard)

let isNumberColumn (name: string) =
    let name = name.ToLowerInvariant()
    name.Contains "account number" || name.Contains "card number"

// ── CSV ─────────────────────────────────────────────────────────────────────

let fields (line: string) =
    let fields = ResizeArray<string>()
    let field = StringBuilder()
    let mutable quoted = false
    let mutable index = 0

    while index < line.Length do
        match line[index] with
        | '"' when quoted && index + 1 < line.Length && line[index + 1] = '"' ->
            field.Append '"' |> ignore
            index <- index + 1
        | '"' -> quoted <- not quoted
        | ',' when not quoted ->
            fields.Add(field.ToString())
            field.Clear() |> ignore
        | char -> field.Append char |> ignore

        index <- index + 1

    fields.Add(field.ToString())
    List.ofSeq fields

let quote (field: string) =
    if field.IndexOfAny [| ','; '"'; '\n'; '\r' |] >= 0 then
        "\"" + field.Replace("\"", "\"\"") + "\""
    else
        field

// ── Main ────────────────────────────────────────────────────────────────────

let text = File.ReadAllText input
let newline = if text.Contains "\r\n" then "\r\n" else "\n"
let lines = text.Replace("\r\n", "\n").Split '\n'

let isKnownColumn (name: string) =
    let name = name.Trim().ToLowerInvariant()
    freeTextColumns.Contains name || isNumberColumn name

// The header is the first line of several columns that names a known column.
// Lines before it are the preamble.
let headerIndex =
    lines
    |> Array.tryFindIndex (fun line ->
        let names = fields line
        names.Length > 1 && List.exists isKnownColumn names)
    |> Option.defaultWith (fun () ->
        eprintfn $"{input}: found no header with a known column"
        exit 1)

let header = fields lines[headerIndex] |> List.map (fun name -> name.Trim())

let replaceField (column: string) (value: string) =
    let name = column.ToLowerInvariant()

    if isNumberColumn name then replaceNumbers value
    elif freeTextColumns.Contains name then replaceText value
    else value

let anonymised =
    lines
    |> Array.mapi (fun index line ->
        if index < headerIndex then
            replaceNumbers line
        elif index = headerIndex || String.IsNullOrWhiteSpace line then
            line
        else
            let values = fields line

            if values.Length <> header.Length then
                eprintfn $"{input} line {index + 1}: expected {header.Length} fields, found {values.Length}"
                exit 1

            List.map2 replaceField header values |> List.map quote |> String.concat ",")

File.WriteAllText(output, String.Join(newline, anonymised))
printfn $"Anonymised {input} into {output}"
