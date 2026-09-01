import budgeteur/transaction/transaction.{type Transaction}
import gleam/dynamic/decode
import gleam/json

/// localStorage key for the whole transactions payload.
pub const storage_key = "budgeteur.transactions"

pub fn data_decoder() -> decode.Decoder(List(Transaction)) {
  decode.field(
    "transactions",
    decode.list(transaction.transaction_decoder()),
    fn(transactions) { decode.success(transactions) },
  )
}

pub fn data_to_json(transactions: List(Transaction)) -> json.Json {
  json.object([
    #("transactions", json.array(transactions, transaction.transaction_to_json)),
  ])
}

pub fn data_to_string(transactions: List(Transaction)) -> String {
  data_to_json(transactions) |> json.to_string
}
