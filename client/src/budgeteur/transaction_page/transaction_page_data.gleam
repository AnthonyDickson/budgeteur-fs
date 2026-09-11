import budgeteur/tag.{type Tag}
import budgeteur/transaction_page/transaction.{type Transaction}
import gleam/dynamic/decode
import gleam/json

/// localStorage key for the whole transactions payload.
pub const storage_key = "budgeteur.transactions"

pub type TransactionPageData {
  TransactionPageData(transactions: List(Transaction), tags: List(Tag))
}

pub fn data_decoder() -> decode.Decoder(TransactionPageData) {
  use transactions <- decode.field(
    "transactions",
    decode.list(transaction.transaction_decoder()),
  )

  use tags <- decode.field("tags", decode.list(tag.tag_decoder()))

  decode.success(TransactionPageData(transactions:, tags:))
}

pub fn data_to_json(data: TransactionPageData) -> json.Json {
  json.object([
    #(
      "transactions",
      json.array(data.transactions, transaction.transaction_to_json),
    ),
    #("tags", json.array(data.tags, tag.tag_to_json)),
  ])
}

pub fn to_string(data: TransactionPageData) -> String {
  data_to_json(data) |> json.to_string
}
