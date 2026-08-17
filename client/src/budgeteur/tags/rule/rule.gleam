import gleam/dynamic/decode
import gleam/json
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

fn uuid_decoder() -> decode.Decoder(Uuid) {
  decode.string
  |> decode.then(fn(s) {
    case uuid.from_string(s) {
      Ok(uuid) -> decode.success(uuid)
      Error(Nil) -> decode.failure(uuid.nil, "Uuid")
    }
  })
}

pub fn rule_decoder() -> decode.Decoder(Rule) {
  use id <- decode.field("id", uuid_decoder())
  use pattern <- decode.field("pattern", decode.string)
  use tag_id <- decode.field("tagId", uuid_decoder())
  decode.success(Rule(id:, pattern:, tag_id:))
}

pub fn rule_to_json(rule: Rule) -> json.Json {
  let Rule(id:, pattern:, tag_id:) = rule
  json.object([
    #("id", json.string(uuid.to_string(id))),
    #("pattern", json.string(pattern)),
    #("tagId", json.string(uuid.to_string(tag_id))),
  ])
}
