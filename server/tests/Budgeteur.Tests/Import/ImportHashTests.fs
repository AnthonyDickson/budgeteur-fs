namespace Budgeteur.Tests.Import

module ImportHashTests =
    open Expecto

    open Budgeteur.Domain.Account
    open Budgeteur.Feature.Import

    let private parseRows fileName text =
        match Statement.parse Formats.all fileName text with
        | Ok statement -> statement.Rows
        | Error errors -> failtestf "expected %s to parse: %A" fileName errors

    let private hashes fileName text =
        parseRows fileName text |> List.map _.ImportHash

    let private firstHash fileName text =
        match hashes fileName text with
        | hash :: _ -> hash
        | [] -> failtestf "expected %s to have rows" fileName

    let private kiwibankText (rows : string list) =
        String.concat "\n" (Formats.kiwibank.Header :: rows)

    // Pinned: the values were computed independently with sha256sum. If a
    // refactor changes them, every stored hash stops matching and re-imports
    // duplicate every transaction.
    [<Tests>]
    let pinnedTests =
        testList "ImportHash pinned values" [
            testCase "the hash input is the version, number, and fields"
            <| fun () ->
                let number =
                    AccountNumber.create "12-3456-0789012-00"
                    |> Result.defaultWith (failtestf "%A")

                Expect.equal
                    (ImportHash.compute number [ "abc" ])
                    ("fe43126b21eca011af6edc60abaeb242"
                     + "0d44d969ce1086a27374e3b7f6e2e3bd")
                    "length-prefixed parts, SHA-256, lowercase hex"

            testCase "Kiwibank hashes the processing date, amount, and balance"
            <| fun () ->
                Expect.equal
                    (firstHash
                        "KiwibankChequing.csv"
                        (Fixture.read "KiwibankChequing.csv"))
                    ("7e47e795e223ab5f00637c79d242f979"
                     + "b125920ce61709f51019028a310a6ae6")
                    "2026-03-28, -8.50, 920.21 in 12-3456-0789012-000"

            testCase "ASB card hashes the unique id"
            <| fun () ->
                Expect.equal
                    (firstHash "AsbCard.csv" (Fixture.read "AsbCard.csv"))
                    ("851b143621337576ae3c43edfa3949ac"
                     + "f430c06987388881e71e5a04d4d99117")
                    "2026061701 on XXXX-XXXX-XXXX-0000"
        ]

    [<Tests>]
    let identityTests =
        let row description amount balance =
            $"12-3456-0789012-00,2026-03-01,2026-03-02,{description},\
            EFTPOS PURCHASE,,,,,,,,,{amount},{balance}"

        testList "ImportHash identity fields" [
            testCase "every row in the fixtures has its own hash"
            <| fun () ->
                for name in
                    [
                        "KiwibankChequing.csv"
                        "KiwibankSavings.csv"
                        "AsbCard.csv"
                    ] do
                    let hashes = hashes name (Fixture.read name)

                    Expect.equal
                        (List.distinct hashes)
                        hashes
                        $"no two rows of {name} share a hash"

            testCase "a changed description or format keeps the hash"
            <| fun () ->
                // Descriptions and quoting are not identity fields, so an
                // export that reworded them still matches.
                Expect.equal
                    (firstHash
                        "a.csv"
                        (kiwibankText [ row "CAFE" "-4.50" "10.00" ]))
                    (firstHash
                        "b.csv"
                        (kiwibankText [ row "\"Cafe, Auckland\"" "-4.5" "10" ]))
                    "the same date, amount, and balance"

            testCase "identical purchases on a day differ by balance"
            <| fun () ->
                let hashes =
                    hashes
                        "twice.csv"
                        (kiwibankText [
                            row "CAFE" "-4.50" "10.00"
                            row "CAFE" "-4.50" "5.50"
                        ])

                Expect.equal
                    (List.length (List.distinct hashes))
                    2
                    "the running balance tells them apart"

            testCase "the same row in another account differs"
            <| fun () ->
                let chequing = row "CAFE" "-4.50" "10.00"
                let savings = chequing.Replace ("-00,", "-01,")

                Expect.notEqual
                    (firstHash "a.csv" (kiwibankText [ chequing ]))
                    (firstHash "b.csv" (kiwibankText [ savings ]))
                    "the account number is part of the hash"
        ]
