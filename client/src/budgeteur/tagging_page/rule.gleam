import budgeteur/shared/uuid as uuid_codec
import gleam/dynamic/decode
import gleam/json
import gleam/option.{None}
import youid/uuid.{type Uuid}

pub type Rule {
  Rule(
    // Unique identifier for the rule.
    id: Uuid,
    // Literal substring matched against transaction descriptions.
    pattern: String,
    // What the rule proposes for matching transactions.
    target: Target,
  )
}

/// What a rule proposes when it wins. Auto-tagging applies a rule's tag; a
/// rule's transfer is only suggested in quick tagging.
pub type Target {
  TagTarget(tag_id: Uuid)
  TransferTarget
}

pub fn rule_decoder() -> decode.Decoder(Rule) {
  use id <- decode.field("id", uuid_codec.decoder())
  use pattern <- decode.field("pattern", decode.string)
  use target <- decode.then(target_decoder())
  decode.success(Rule(id:, pattern:, target:))
}

/// The server sends a target as a kind and an optional tag id, since its
/// OpenAPI document cannot describe a union with fields.
pub fn target_decoder() -> decode.Decoder(Target) {
  use kind <- decode.field("target", decode.string)
  use tag_id <- decode.optional_field(
    "tagId",
    None,
    decode.optional(uuid_codec.decoder()),
  )
  case kind, tag_id {
    "Tag", option.Some(tag_id) -> decode.success(TagTarget(tag_id))
    "Transfer", None -> decode.success(TransferTarget)
    _, _ -> decode.failure(TransferTarget, "Target")
  }
}

/// The target's fields of a request: the kind, and the tag id for a tag.
pub fn target_fields(target: Target) -> List(#(String, json.Json)) {
  case target {
    TagTarget(tag_id:) -> [
      #("target", json.string("Tag")),
      #("tagId", json.string(uuid.to_string(tag_id))),
    ]
    TransferTarget -> [#("target", json.string("Transfer"))]
  }
}

/// Whether the rule proposes the tag.
pub fn targets_tag(rule: Rule, tag_id: Uuid) -> Bool {
  rule.target == TagTarget(tag_id)
}
