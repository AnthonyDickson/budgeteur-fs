namespace Budgeteur.Domain.Vectoriser

open System
open System.Collections.Generic
open System.Text.RegularExpressions

open Budgeteur.Domain.Money
open Budgeteur.Domain.Transaction

/// <summary>The kinds of feature a transaction has. See decision 3 in
/// docs/smart-tagging.md.</summary>
[<RequireQualifiedAccess>]
type Block =
    /// <summary>Character n-grams of the normalised description.</summary>
    | Chars
    /// <summary>Word tokens of the normalised description.</summary>
    | Words
    /// <summary>The amount's sign, and its sign and size bucket.</summary>
    | Amount
    /// <summary>The account.</summary>
    | Account

/// <summary>A column of the feature matrix: a term within its block.</summary>
type Feature = { Block : Block; Term : string }

/// <summary>A transaction's non-zero features, by column, in ascending column
/// order.</summary>
type FeatureVector = {
    Columns : int array
    Values : float array
}

/// <summary>The columns and IDF weights learned from a training set. Terms and
/// categories the training set lacks are ignored by
/// <c>Vectoriser.transform</c>.</summary>
type Vectoriser = private {
    Features : Feature array
    /// <summary>Each block's columns by term.</summary>
    Columns : Map<Block, IReadOnlyDictionary<string, int>>
    /// <summary>The IDF weight by column, for the text blocks'
    /// columns.</summary>
    Idf : float array
}

/// <summary>The vectoriser of decision 3 in docs/smart-tagging.md. It
/// reproduces scikit-learn's <c>TfidfVectorizer</c> and <c>OneHotEncoder</c>
/// as the experiments configured them, so the parity tests can compare the two
/// term by term.</summary>
module Vectoriser =
    let private digits = Regex (@"\d+", RegexOptions.CultureInvariant)

    /// <summary>A description with case folded as rules fold it, digit runs
    /// replaced by <c>#</c>, and whitespace collapsed, so store and reference
    /// numbers do not split one merchant into many.</summary>
    let normalise (description : string) : string =
        let replaced = digits.Replace (description.ToUpperInvariant (), "#")

        replaced.Split (
            (null : char array),
            StringSplitOptions.RemoveEmptyEntries
        )
        |> String.concat " "

    let private words (normalised : string) : string array =
        normalised.Split (' ', StringSplitOptions.RemoveEmptyEntries)

    /// <summary>Character n-grams of 3 to 5 characters within each word padded
    /// by a space on either side, as scikit-learn's <c>char_wb</c> analyser
    /// makes them: a padded word shorter than 5 characters has no n-grams
    /// longer than itself.</summary>
    let private ngrams (normalised : string) : string array = [|
        for word in words normalised do
            let padded = $" {word} "

            for n in 3 .. min 5 padded.Length do
                for offset in 0 .. padded.Length - n ->
                    padded.Substring (offset, n)
    |]

    /// <summary>The amount's sign, and its sign with the base 2 logarithm of
    /// its size plus one, rounded down. Named as scikit-learn names the
    /// categories.</summary>
    let private amountTerms (amount : decimal) : string array =
        let sign = if amount < 0m then "-" else "+"
        let bucket = Math.Floor (Math.Log2 (float (abs amount) + 1.0))
        [| $"sign_{sign}"; $"bucket_{sign}%i{int bucket}" |]

    /// <summary>An account's category: its id, or the empty string for a
    /// transaction without one.</summary>
    let private accountTerm (accountId : Guid option) : string =
        accountId |> Option.map string |> Option.defaultValue ""

    /// <summary>Each block's terms for a transaction, with repeats.</summary>
    let private terms
        (transaction : Transaction)
        : (Block * string array) list =
        let normalised =
            normalise (TransactionDescription.value transaction.Description)

        [
            Block.Chars, ngrams normalised
            Block.Words, words normalised
            Block.Amount, amountTerms (Money.value transaction.Amount)
            Block.Account, [| accountTerm transaction.AccountId |]
        ]

    let private isText (block : Block) =
        match block with
        | Block.Chars
        | Block.Words -> true
        | Block.Amount
        | Block.Account -> false

    /// <summary>Learn the columns and IDF weights from a training set's
    /// transactions. Columns are ordered by block, then term, so they do not
    /// depend on the order of the transactions. IDF is smoothed and counts
    /// documents, not occurrences: <c>ln((1 + n) / (1 + df)) + 1</c>.</summary>
    /// <remarks>Counts terms in mutable dictionaries for speed, since a fit
    /// runs on every queue read; the function is still pure.</remarks>
    let fit (transactions : Transaction list) : Vectoriser =
        // How many transactions have each term, by block.
        let frequencies = Dictionary<Block, Dictionary<string, int>>()

        for transaction in transactions do
            for block, terms in terms transaction do
                let counts =
                    match frequencies.TryGetValue block with
                    | true, counts -> counts
                    | false, _ ->
                        let counts =
                            Dictionary<string, int> StringComparer.Ordinal

                        frequencies[block] <- counts
                        counts

                for term in HashSet<string>(terms, StringComparer.Ordinal) do
                    match counts.TryGetValue term with
                    | true, count -> counts[term] <- count + 1
                    | false, _ -> counts[term] <- 1

        let byBlock =
            frequencies
            |> Seq.map (fun pair ->
                let terms =
                    pair.Value
                    |> Seq.map (fun count -> count.Key, count.Value)
                    |> Array.ofSeq

                Array.sortInPlaceWith
                    (fun (a, _) (b, _) -> String.CompareOrdinal (a, b))
                    terms

                pair.Key, terms)
            |> Array.ofSeq
            |> Array.sortBy fst

        let documents = float (List.length transactions)

        let features = [|
            for block, terms in byBlock do
                for term, _ in terms -> { Block = block; Term = term }
        |]

        {
            Features = features
            Columns =
                features
                |> Array.mapi (fun column feature -> feature, column)
                |> Array.groupBy (fun (feature, _) -> feature.Block)
                |> Array.map (fun (block, columns) ->
                    let lookup = Dictionary<string, int> StringComparer.Ordinal

                    for feature, column in columns do
                        lookup[feature.Term] <- column

                    block, lookup :> IReadOnlyDictionary<string, int>)
                |> Map.ofArray
            Idf = [|
                for _, terms in byBlock do
                    for _, frequency in terms ->
                        log ((1.0 + documents) / (1.0 + float frequency)) + 1.0
            |]
        }

    /// <summary>The features by column.</summary>
    let features (vectoriser : Vectoriser) : Feature array = vectoriser.Features

    /// <summary>A transaction's features: each text block's term counts times
    /// their IDF, scaled to unit length on its own; each category as 1. Terms
    /// and categories without a column are ignored.</summary>
    let transform
        (vectoriser : Vectoriser)
        (transaction : Transaction)
        : FeatureVector =
        let entries = Dictionary<int, float>()

        for block, terms in terms transaction do
            match Map.tryFind block vectoriser.Columns with
            | None -> ()
            | Some columns ->
                let counts = Dictionary<int, float>()

                for term in terms do
                    match columns.TryGetValue term with
                    | true, column ->
                        match counts.TryGetValue column with
                        | true, count -> counts[column] <- count + 1.0
                        | false, _ -> counts[column] <- 1.0
                    | false, _ -> ()

                if isText block then
                    let mutable squares = 0.0

                    for count in counts do
                        let value = count.Value * vectoriser.Idf[count.Key]
                        squares <- squares + value * value

                    let norm = sqrt squares

                    for count in counts do
                        entries[count.Key] <-
                            count.Value * vectoriser.Idf[count.Key] / norm
                else
                    for count in counts do
                        entries[count.Key] <- 1.0

        let columns = Array.ofSeq entries.Keys
        let values = columns |> Array.map (fun column -> entries[column])
        Array.Sort (columns, values)
        { Columns = columns; Values = values }
