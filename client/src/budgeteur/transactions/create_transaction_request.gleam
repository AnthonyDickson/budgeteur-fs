import budgeteur/date
import budgeteur/money
import gleam/json
import gleam/time/calendar.{type Date}

pub type CreateTransactionRequest {
  CreateTransactionRequest(
    amount: Float,
    description: String,
    date: Date,
    is_transfer: Bool,
  )
}

pub fn create_transaction_request_to_json(
  create_transaction_request: CreateTransactionRequest,
) -> json.Json {
  let CreateTransactionRequest(amount:, description:, date:, is_transfer:) =
    create_transaction_request
  json.object([
    #("amount", money.encode_decimal(amount)),
    #("description", json.string(description)),
    #("date", date.encode(date)),
    #("isTransfer", json.bool(is_transfer)),
  ])
}
