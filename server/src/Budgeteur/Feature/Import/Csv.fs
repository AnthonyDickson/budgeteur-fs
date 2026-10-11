namespace Budgeteur.Feature.Import

open System
open System.Text

/// <summary>A non-blank line of a CSV file and its 1-based line number in the
/// file, so errors can point at it.</summary>
type CsvLine = { Number : int; Text : string }

/// <summary>Where <c>Csv.fields</c> is within a line.</summary>
type private FieldState =
    /// <summary>At the start of a field.</summary>
    | Start
    /// <summary>In a field without quotes.</summary>
    | Unquoted
    /// <summary>In a quoted field.</summary>
    | Quoted
    /// <summary>After a quote in a quoted field: a closing quote, or the
    /// first of a doubled one.</summary>
    | QuoteInQuoted

/// <summary>Reads the text of a bank's CSV export. Statements are UTF-8 with
/// comma separators, and no field spans lines (see Assumptions in
/// docs/csv-import.md).</summary>
module Csv =
    /// <summary>U+FEFF, which some systems write at the start of a UTF-8
    /// file.</summary>
    let private byteOrderMark = char 0xFEFF

    /// <summary>The file's non-blank lines. A UTF-8 byte order mark is
    /// dropped and any line ending is accepted, so exports from different
    /// systems read the same. Line numbers count the blank lines that are
    /// skipped.</summary>
    let lines (text : string) : CsvLine list =
        text
            .TrimStart(byteOrderMark)
            .Replace("\r\n", "\n")
            .Replace('\r', '\n')
            .Split
            '\n'
        |> Seq.mapi (fun index text -> { Number = index + 1; Text = text })
        |> Seq.filter (fun line -> not (String.IsNullOrWhiteSpace line.Text))
        |> List.ofSeq

    /// <summary>Split a line into its comma-separated fields. A field in double
    /// quotes may contain commas, and a doubled quote inside it stands for one
    /// quote. Fails on an unterminated quote or text after a closing
    /// quote.</summary>
    let fields (line : string) : Result<string list, string> =
        let fields = ResizeArray<string>()
        let field = StringBuilder ()
        let mutable state = Start
        let mutable error = None

        let endField () =
            fields.Add (field.ToString ())
            field.Clear () |> ignore
            state <- Start

        for index in 0 .. line.Length - 1 do
            if Option.isNone error then
                match state, line[index] with
                | Start, '"' -> state <- Quoted
                | (Start | Unquoted), ',' -> endField ()
                | (Start | Unquoted), char ->
                    field.Append char |> ignore
                    state <- Unquoted
                | Quoted, '"' -> state <- QuoteInQuoted
                | Quoted, char -> field.Append char |> ignore
                | QuoteInQuoted, '"' ->
                    field.Append '"' |> ignore
                    state <- Quoted
                | QuoteInQuoted, ',' -> endField ()
                | QuoteInQuoted, _ ->
                    error <-
                        Some
                            $"unexpected text after a closing quote at \
                            column {index + 1}"

        match error, state with
        | Some error, _ -> Error error
        | None, Quoted -> Error "a quoted field has no closing quote"
        | None, _ ->
            fields.Add (field.ToString ())
            Ok (List.ofSeq fields)
