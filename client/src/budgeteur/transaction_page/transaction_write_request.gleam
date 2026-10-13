import budgeteur/shared/date
import budgeteur/shared/money
import gleam/json
import gleam/option.{type Option}
import gleam/time/calendar.{type Date}
import youid/uuid.{type Uuid}

pub type TransactionWriteRequest {
  TransactionWriteRequest(
    amount: Float,
    description: String,
    date: Date,
    is_transfer: Bool,
    tag_id: Option(Uuid),
    account_id: Option(Uuid),
  )
}

pub fn to_json(
  transaction_write_request: TransactionWriteRequest,
) -> json.Json {
  let TransactionWriteRequest(
    amount:,
    description:,
    date:,
    is_transfer:,
    tag_id:,
    account_id:,
  ) = transaction_write_request
  json.object([
    #("amount", money.encode_decimal(amount)),
    #("description", json.string(description)),
    #("date", date.encode(date)),
    #("isTransfer", json.bool(is_transfer)),
    #("tagId", json.nullable(tag_id |> option.map(uuid.to_string), json.string)),
    #(
      "accountId",
      json.nullable(account_id |> option.map(uuid.to_string), json.string),
    ),
  ])
}
