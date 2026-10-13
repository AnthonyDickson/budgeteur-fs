namespace Budgeteur.Tests.Import

module CsvTests =
    open Expecto

    open Budgeteur.Feature.Import

    [<Tests>]
    let tests =
        testList "Csv" [
            testCase "lines normalise endings and skip blank lines"
            <| fun () ->
                let text =
                    string (char 0xFEFF) + "a,b\r\n\r\nc,d\re,f\n  \ng,h\n"

                Expect.equal
                    (Csv.lines text)
                    [
                        { Number = 1; Text = "a,b" }
                        { Number = 3; Text = "c,d" }
                        { Number = 4; Text = "e,f" }
                        { Number = 6; Text = "g,h" }
                    ]
                    "a BOM and blank lines are dropped, line numbers kept"

            testCase "fields split on commas outside quotes"
            <| fun () ->
                Expect.equal
                    (Csv.fields "2026/06/17,\"CITY, AUCKLAND\",,707.00")
                    (Ok [ "2026/06/17"; "CITY, AUCKLAND"; ""; "707.00" ])
                    "a quoted comma is part of the field, an empty field stays"

                Expect.equal
                    (Csv.fields "\"say \"\"hi\"\"\",x")
                    (Ok [ "say \"hi\""; "x" ])
                    "a doubled quote is one quote"

                Expect.equal
                    (Csv.fields "a,")
                    (Ok [ "a"; "" ])
                    "a trailing comma ends with an empty field"

                Expect.equal
                    (Csv.fields "Café Māori,ō")
                    (Ok [ "Café Māori"; "ō" ])
                    "non-ASCII text is kept"

            testCase "fields reject malformed quotes"
            <| fun () ->
                Expect.isError
                    (Csv.fields "\"unterminated,x")
                    "an unterminated quote"

                Expect.isError
                    (Csv.fields "\"closed\"text,x")
                    "text after a closing quote"
        ]
