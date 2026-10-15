//// A search of the user's transactions: the criteria as the page's controls
//// hold them, their validation, the request the page sends, and the page of
//// matches the server returns. See docs/transaction-search.md.

import budgeteur/shared/date
import budgeteur/shared/money
import budgeteur/transaction_page/transaction.{type Transaction}
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import gleam/time/calendar.{type Date}
import youid/uuid.{type Uuid}

/// The longest text the server accepts: a rule pattern's maximum length.
pub const max_text_length = 128

/// A named date range the server resolves from the client's today, or custom
/// dates.
pub type DatePreset {
  AnyTime
  ThisMonth
  LastMonth
  ThisYear
  LastYear
  /// From 1 April.
  ThisFinancialYear
  LastFinancialYear
  Custom
}

pub const date_presets = [
  AnyTime,
  ThisMonth,
  LastMonth,
  ThisYear,
  LastYear,
  ThisFinancialYear,
  LastFinancialYear,
  Custom,
]

/// Which account a match has.
pub type AccountFilter {
  AnyAccount
  NoAccount
  OneAccount(Uuid)
}

/// How a match is categorised.
pub type TagFilter {
  AnyTag
  /// Untagged or dismissed.
  WithoutTag
  Untagged
  Dismissed
  Transfer
  OneTag(Uuid)
}

/// The sign of a match's amount: a credit is positive and a debit negative,
/// so a zero amount matches only `AnyDirection`.
pub type Direction {
  AnyDirection
  Credit
  Debit
}

pub const directions = [AnyDirection, Credit, Debit]

/// The criteria of a search as the page's controls hold them. A search
/// matches the transactions meeting all of them; with none set, every
/// transaction.
pub type Search {
  Search(
    /// Text the description contains, ignoring case. Blank sets no criterion.
    text: String,
    preset: DatePreset,
    /// The custom first day's input, inclusive. Blank for none.
    from: String,
    /// The custom last day's input, inclusive. Blank for none.
    to: String,
    account: AccountFilter,
    tag: TagFilter,
    direction: Direction,
    /// The smallest absolute amount's input, inclusive. Blank for none.
    minimum: String,
    /// The largest absolute amount's input, inclusive. Blank for none.
    maximum: String,
  )
}

/// A search whose inputs are valid, ready to send.
pub type Criteria {
  Criteria(
    text: String,
    preset: DatePreset,
    from: Option(Date),
    to: Option(Date),
    account: AccountFilter,
    tag: TagFilter,
    direction: Direction,
    minimum: Option(Float),
    maximum: Option(Float),
  )
}

/// Why a search cannot be sent, by field.
pub type Invalid {
  Invalid(
    /// The custom dates' error.
    dates: Option(String),
    minimum: Option(String),
    maximum: Option(String),
  )
}

/// A page of a search's matches.
pub type Page {
  Page(
    /// Newest first, then by id.
    transactions: List(Transaction),
    /// Where the next page starts, or None on the last page. Opaque.
    next: Option(String),
    /// The dates criterion's first day, with a preset resolved.
    from: Option(Date),
    /// The dates criterion's last day, with a preset resolved.
    to: Option(Date),
  )
}

/// The search with no criteria set, which matches every transaction.
pub fn new() -> Search {
  Search(
    text: "",
    preset: AnyTime,
    from: "",
    to: "",
    account: AnyAccount,
    tag: AnyTag,
    direction: AnyDirection,
    minimum: "",
    maximum: "",
  )
}

pub fn preset_to_string(preset: DatePreset) -> String {
  case preset {
    AnyTime -> "AnyTime"
    ThisMonth -> "ThisMonth"
    LastMonth -> "LastMonth"
    ThisYear -> "ThisYear"
    LastYear -> "LastYear"
    ThisFinancialYear -> "ThisFinancialYear"
    LastFinancialYear -> "LastFinancialYear"
    Custom -> "Custom"
  }
}

pub fn parse_preset(value: String) -> Result(DatePreset, Nil) {
  case value {
    "AnyTime" -> Ok(AnyTime)
    "ThisMonth" -> Ok(ThisMonth)
    "LastMonth" -> Ok(LastMonth)
    "ThisYear" -> Ok(ThisYear)
    "LastYear" -> Ok(LastYear)
    "ThisFinancialYear" -> Ok(ThisFinancialYear)
    "LastFinancialYear" -> Ok(LastFinancialYear)
    "Custom" -> Ok(Custom)
    _ -> Error(Nil)
  }
}

pub fn preset_label(preset: DatePreset) -> String {
  case preset {
    AnyTime -> "Any time"
    ThisMonth -> "This month"
    LastMonth -> "Last month"
    ThisYear -> "This year"
    LastYear -> "Last year"
    ThisFinancialYear -> "This financial year"
    LastFinancialYear -> "Last financial year"
    Custom -> "Custom"
  }
}

/// How many criteria other than text are set, which the "Filters" button
/// shows.
pub fn filter_count(search: Search) -> Int {
  let dates = case search.preset, search.from, search.to {
    AnyTime, _, _ | Custom, "", "" -> 0
    _, _, _ -> 1
  }
  let account = case search.account {
    AnyAccount -> 0
    NoAccount | OneAccount(_) -> 1
  }
  let tag = case search.tag {
    AnyTag -> 0
    WithoutTag | Untagged | Dismissed | Transfer | OneTag(_) -> 1
  }
  let amount = case search.direction, search.minimum, search.maximum {
    AnyDirection, "", "" -> 0
    _, _, _ -> 1
  }
  dates + account + tag + amount
}

pub fn direction_to_string(direction: Direction) -> String {
  case direction {
    AnyDirection -> "Any"
    Credit -> "Credit"
    Debit -> "Debit"
  }
}

pub fn parse_direction(value: String) -> Direction {
  case value {
    "Credit" -> Credit
    "Debit" -> Debit
    _ -> AnyDirection
  }
}

/// The account select's value for the filter.
pub fn account_to_value(filter: AccountFilter) -> String {
  case filter {
    AnyAccount -> "Any"
    NoAccount -> "NoAccount"
    OneAccount(id) -> uuid.to_string(id)
  }
}

/// The filter for the account select's value.
pub fn parse_account(value: String) -> AccountFilter {
  case value, uuid.from_string(value) {
    "NoAccount", _ -> NoAccount
    _, Ok(id) -> OneAccount(id)
    _, Error(Nil) -> AnyAccount
  }
}

/// The tag select's value for the filter.
pub fn tag_to_value(filter: TagFilter) -> String {
  case filter {
    AnyTag -> "Any"
    WithoutTag -> "WithoutTag"
    Untagged -> "Untagged"
    Dismissed -> "Dismissed"
    Transfer -> "Transfer"
    OneTag(id) -> uuid.to_string(id)
  }
}

/// The filter for the tag select's value.
pub fn parse_tag(value: String) -> TagFilter {
  case value, uuid.from_string(value) {
    "WithoutTag", _ -> WithoutTag
    "Untagged", _ -> Untagged
    "Dismissed", _ -> Dismissed
    "Transfer", _ -> Transfer
    _, Ok(id) -> OneTag(id)
    _, Error(Nil) -> AnyTag
  }
}

/// Whether any criterion is set. Blank text sets none.
pub fn is_set(search: Search) -> Bool {
  string.trim(search.text) != "" || filter_count(search) > 0
}

fn optional_date(input: String) -> Result(Option(Date), String) {
  case string.trim(input) {
    "" -> Ok(None)
    input ->
      case date.parse(input) {
        Ok(date) -> Ok(Some(date))
        Error(Nil) -> Error("Enter a valid date")
      }
  }
}

fn dates(search: Search) -> Result(#(Option(Date), Option(Date)), String) {
  case search.preset {
    Custom -> {
      case optional_date(search.from), optional_date(search.to) {
        Ok(Some(from)), Ok(Some(to)) ->
          case calendar.naive_date_compare(from, to) {
            order.Gt -> Error("The first day must be on or before the last day")
            _ -> Ok(#(Some(from), Some(to)))
          }
        Ok(from), Ok(to) -> Ok(#(from, to))
        Error(error), _ | _, Error(error) -> Error(error)
      }
    }
    _ -> Ok(#(None, None))
  }
}

/// A size is the absolute amount: zero or more. The inputs keep at most two
/// decimal places.
fn size(input: String) -> Result(Option(Float), String) {
  case string.trim(input) {
    "" -> Ok(None)
    input ->
      case money.parse_decimal(input) {
        Ok(amount) if amount >=. 0.0 -> Ok(Some(amount))
        Ok(_) -> Error("Enter zero or more")
        Error(Nil) -> Error("Enter an amount, e.g. 12.50")
      }
  }
}

fn sizes(
  search: Search,
) -> #(Result(Option(Float), String), Result(Option(Float), String)) {
  case size(search.minimum), size(search.maximum) {
    Ok(Some(minimum)), Ok(Some(maximum)) if minimum >. maximum -> #(
      Error("The minimum cannot be more than the maximum"),
      Ok(Some(maximum)),
    )
    minimum, maximum -> #(minimum, maximum)
  }
}

fn error_of(result: Result(a, String)) -> Option(String) {
  case result {
    Ok(_) -> None
    Error(error) -> Some(error)
  }
}

/// Check the search's inputs. Invalid input runs no search.
pub fn validate(search: Search) -> Result(Criteria, Invalid) {
  let dates = dates(search)
  let #(minimum, maximum) = sizes(search)
  case dates, minimum, maximum {
    Ok(#(from, to)), Ok(minimum), Ok(maximum) ->
      Ok(Criteria(
        text: search.text,
        preset: search.preset,
        from:,
        to:,
        account: search.account,
        tag: search.tag,
        direction: search.direction,
        minimum:,
        maximum:,
      ))
    _, _, _ ->
      Error(Invalid(
        dates: error_of(dates),
        minimum: error_of(minimum),
        maximum: error_of(maximum),
      ))
  }
}

/// The request for the page of the criteria's matches starting at the
/// cursor, or the first page. The server resolves date presets from `today`.
pub fn request_json(
  criteria: Criteria,
  today: Date,
  cursor: Option(String),
) -> json.Json {
  let state = fn(state, id) {
    json.object([
      #("state", json.string(state)),
      #("id", json.nullable(id, fn(id) { json.string(uuid.to_string(id)) })),
    ])
  }
  let account = case criteria.account {
    AnyAccount -> state("Any", None)
    NoAccount -> state("NoAccount", None)
    OneAccount(id) -> state("Account", Some(id))
  }
  let tag = case criteria.tag {
    AnyTag -> state("Any", None)
    WithoutTag -> state("WithoutTag", None)
    Untagged -> state("Untagged", None)
    Dismissed -> state("Dismissed", None)
    Transfer -> state("Transfer", None)
    OneTag(id) -> state("Tag", Some(id))
  }
  json.object([
    #(
      "criteria",
      json.object([
        #("text", json.string(criteria.text)),
        #(
          "dates",
          json.object([
            #("preset", json.string(preset_to_string(criteria.preset))),
            #("from", json.nullable(criteria.from, date.encode)),
            #("to", json.nullable(criteria.to, date.encode)),
          ]),
        ),
        #("account", account),
        #("tag", tag),
        #(
          "amount",
          json.object([
            #("direction", json.string(direction_to_string(criteria.direction))),
            #("minimum", json.nullable(criteria.minimum, money.encode_decimal)),
            #("maximum", json.nullable(criteria.maximum, money.encode_decimal)),
          ]),
        ),
      ]),
    ),
    #("today", date.encode(today)),
    #("cursor", json.nullable(cursor, json.string)),
  ])
}

pub fn page_decoder() -> decode.Decoder(Page) {
  use transactions <- decode.field(
    "transactions",
    decode.list(transaction.transaction_decoder()),
  )
  use next <- decode.optional_field(
    "cursor",
    None,
    decode.optional(decode.string),
  )
  use from <- decode.optional_field(
    "from",
    None,
    decode.optional(date.decoder()),
  )
  use to <- decode.optional_field("to", None, decode.optional(date.decoder()))
  decode.success(Page(transactions:, next:, from:, to:))
}
