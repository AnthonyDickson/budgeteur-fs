import budgeteur/transaction_page/transaction
import gleam/json
import gleam/option.{Some}
import gleeunit/should

fn decode_tag_source(source: String) {
  let body = "{
    \"id\": \"00000000-0000-0000-0000-000000000001\",
    \"amount\": \"-12.50\",
    \"description\": \"Coffee\",
    \"date\": \"2026-01-02\",
    \"isTransfer\": false,
    \"tag\": {
      \"id\": \"00000000-0000-0000-0000-00000000000b\",
      \"source\": \"" <> source <> "\"
    }
  }"
  let assert Ok(decoded) = json.parse(body, transaction.transaction_decoder())
  let assert Some(tag) = decoded.tag
  tag.source
}

pub fn every_server_source_decodes_test() {
  decode_tag_source("Manual") |> should.equal(transaction.Manual)
  decode_tag_source("Accepted") |> should.equal(transaction.Accepted)
  decode_tag_source("Rule") |> should.equal(transaction.Rule)
  decode_tag_source("Detected") |> should.equal(transaction.Detected)
}
