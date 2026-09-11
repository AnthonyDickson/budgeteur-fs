import budgeteur/shared/date
import budgeteur/shared/money
import gleam/json
import gleam/option.{type Option}
import gleam/time/calendar.{type Date}
import youid/uuid.{type Uuid}

pub type CreateTransactionRequest {
  CreateTransactionRequest(
    amount: Float,
    description: String,
    date: Date,
    is_transfer: Bool,
    tag_id: Option(Uuid),
  )
}

pub fn create_transaction_request_to_json(
  create_transaction_request: CreateTransactionRequest,
) -> json.Json {
  let CreateTransactionRequest(
    amount:,
    description:,
    date:,
    is_transfer:,
    tag_id:,
  ) = create_transaction_request
  json.object([
    #("amount", money.encode_decimal(amount)),
    #("description", json.string(description)),
    #("date", date.encode(date)),
    #("isTransfer", json.bool(is_transfer)),
    #("tagId", json.nullable(tag_id |> option.map(uuid.to_string), json.string)),
  ])
}
