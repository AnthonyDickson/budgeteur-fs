import budgeteur/money

import gleam/json
import gleam/time/timestamp.{type Timestamp}

pub type CreateTransactionRequest {
  CreateTransactionRequest(amount: Float, description: String, date: Timestamp)
}

pub fn create_transaction_request_to_json(
  create_transaction_request: CreateTransactionRequest,
) -> json.Json {
  let CreateTransactionRequest(amount:, description:, date:) =
    create_transaction_request
  json.object([
    #("amount", money.encode_decimal(amount)),
    #("description", json.string(description)),
    #("date", json.float(timestamp.to_unix_seconds(date))),
  ])
}
