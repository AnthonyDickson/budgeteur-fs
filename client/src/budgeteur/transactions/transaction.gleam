import budgeteur/money
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/option.{type Option, None}
import gleam/result
import gleam/string
import gleam/time/calendar.{type Date, Date}
import youid/uuid.{type Uuid}

pub type Transaction {
  Transaction(
    // <summary>Unique identifier for the transaction item.</summary>
    id: Uuid,
    amount: Float,
    // The title or description of the transaction.</summary>
    description: String,
    // Date when the transaction occurred.
    date: Date,
    import_hash: Option(String),
    account_id: Option(Uuid),
    category_id: Option(Uuid),
  )
}

fn uuid_decoder() -> decode.Decoder(Uuid) {
  decode.string
  |> decode.then(fn(s) {
    case uuid.from_string(s) {
      Ok(uuid) -> decode.success(uuid)
      Error(Nil) -> decode.failure(uuid.nil, "Uuid")
    }
  })
}

/// Parse an ISO-8601 date.
///
/// # Example
///
/// ```gleam
/// let assert Ok(calendar.Date(2026, 8, 9)) = parse_date("2026-08-09")
/// let assert Error(Nil) = parse_date("9 Aug, 2026")
/// ```
fn parse_date(date_string: String) -> Result(Date, Nil) {
  case string.split(date_string, on: "-") {
    [year, month, day] -> {
      use year <- result.try(int.parse(year))
      use month_int <- result.try(int.parse(month))
      use day <- result.try(int.parse(day))
      use month <- result.try(calendar.month_from_int(month_int))
      Ok(Date(year, month, day))
    }
    _ -> Error(Nil)
  }
}

fn date_decoder() -> decode.Decoder(Date) {
  use date_string <- decode.then(decode.string)
  case parse_date(date_string) {
    Ok(date) -> decode.success(date)
    Error(Nil) -> decode.failure(Date(1970, calendar.January, 1), "Date")
  }
}

fn encode_date(date: Date) -> json.Json {
  let year = date.year |> int.to_string |> string.pad_start(4, "0")
  let month =
    date.month
    |> calendar.month_to_int
    |> int.to_string
    |> string.pad_start(2, "0")
  let day = date.day |> int.to_string |> string.pad_start(2, "0")

  json.string(year <> "-" <> month <> "-" <> day)
}

pub fn transaction_decoder() -> decode.Decoder(Transaction) {
  use id <- decode.field("id", uuid_decoder())
  use amount <- decode.field("amount", money.decode_decimal())
  use description <- decode.field("description", decode.string)
  use date <- decode.field("date", date_decoder())
  use import_hash <- decode.optional_field(
    "import_hash",
    None,
    decode.optional(decode.string),
  )
  use account_id <- decode.optional_field(
    "account_id",
    None,
    decode.optional(uuid_decoder()),
  )
  use category_id <- decode.optional_field(
    "category_id",
    None,
    decode.optional(uuid_decoder()),
  )
  decode.success(Transaction(
    id:,
    amount:,
    description:,
    date:,
    import_hash:,
    account_id:,
    category_id:,
  ))
}

pub fn transaction_to_json(transaction: Transaction) -> json.Json {
  let Transaction(
    id:,
    amount:,
    description:,
    date:,
    import_hash:,
    account_id:,
    category_id:,
  ) = transaction
  json.object([
    #("id", json.string(uuid.to_string(id))),
    #("amount", money.encode_decimal(amount)),
    #("description", json.string(description)),
    #("date", encode_date(date)),
    #("import_hash", case import_hash {
      None -> json.null()
      option.Some(value) -> json.string(value)
    }),
    #("account_id", case account_id {
      None -> json.null()
      option.Some(value) -> json.string(uuid.to_string(value))
    }),
    #("category_id", case category_id {
      None -> json.null()
      option.Some(value) -> json.string(uuid.to_string(value))
    }),
  ])
}
