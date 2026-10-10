import budgeteur/shared/uuid as uuid_codec
import gleam/dynamic/decode
import youid/uuid.{type Uuid}

pub type Rule {
  Rule(
    // Unique identifier for the rule.
    id: Uuid,
    // Literal substring matched against transaction descriptions.
    pattern: String,
    // The tag this rule assigns to matching transactions.
    tag_id: Uuid,
  )
}

pub fn rule_decoder() -> decode.Decoder(Rule) {
  use id <- decode.field("id", uuid_codec.decoder())
  use pattern <- decode.field("pattern", decode.string)
  use tag_id <- decode.field("tagId", uuid_codec.decoder())
  decode.success(Rule(id:, pattern:, tag_id:))
}
