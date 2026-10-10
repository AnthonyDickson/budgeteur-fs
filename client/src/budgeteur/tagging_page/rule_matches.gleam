import gleam/dynamic/decode

/// What a rule pattern matches among the user's transactions.
pub type RuleMatches {
  RuleMatches(
    // How many of the user's non-transfer transactions the pattern matches.
    count: Int,
    // Distinct descriptions from the most recent matches, most recent first.
    samples: List(String),
  )
}

pub fn rule_matches_decoder() -> decode.Decoder(RuleMatches) {
  use count <- decode.field("count", decode.int)
  use samples <- decode.field("samples", decode.list(decode.string))
  decode.success(RuleMatches(count:, samples:))
}
