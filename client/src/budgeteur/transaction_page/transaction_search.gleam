//// A search of the user's transactions: the criteria the page sends, and the
//// page of matches the server returns. See docs/transaction-search.md.

import budgeteur/shared/date
import budgeteur/transaction_page/transaction.{type Transaction}
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None}
import gleam/time/calendar.{type Date}

/// The criteria of a search. A search matches the transactions meeting all of
/// them; with none set, every transaction.
pub type Search {
  Search(
    /// Text the description contains, ignoring case. Blank sets no criterion.
    text: String,
  )
}

/// A page of a search's matches.
pub type Page {
  Page(
    /// Newest first, then by id.
    transactions: List(Transaction),
    /// Where the next page starts, or None on the last page. Opaque.
    next: Option(String),
  )
}

/// The search with no criteria set, which matches every transaction.
pub fn new() -> Search {
  Search(text: "")
}

/// The request for the page of the search's matches starting at the cursor,
/// or the first page. The server resolves date presets from `today`.
pub fn request_json(
  search: Search,
  today: Date,
  cursor: Option(String),
) -> json.Json {
  let any_id = fn(state) {
    json.object([#("state", json.string(state)), #("id", json.null())])
  }
  json.object([
    #(
      "criteria",
      json.object([
        #("text", json.string(search.text)),
        #(
          "dates",
          json.object([
            #("preset", json.string("AnyTime")),
            #("from", json.null()),
            #("to", json.null()),
          ]),
        ),
        #("account", any_id("Any")),
        #("tag", any_id("Any")),
        #(
          "amount",
          json.object([
            #("direction", json.string("Any")),
            #("minimum", json.null()),
            #("maximum", json.null()),
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
  decode.success(Page(transactions:, next:))
}
