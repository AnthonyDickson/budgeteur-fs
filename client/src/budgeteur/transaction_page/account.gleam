//// The accounts the transaction form offers. The page reads only the fields it
//// needs, with its own decoder.

import budgeteur/shared/uuid as uuid_decoder
import gleam/dynamic/decode
import youid/uuid.{type Uuid}

pub type Account {
  Account(id: Uuid, name: String)
}

pub fn decoder() -> decode.Decoder(Account) {
  use id <- decode.field("id", uuid_decoder.decoder())
  use name <- decode.field("name", decode.string)
  decode.success(Account(id:, name:))
}
