//// Formatting for counts and other plain numbers shown to the user.

/// Matches the locale in `money.gleam`.
const locale = "en-NZ"

@external(javascript, "./number_ffi.mjs", "formatInteger")
fn format_integer(value: Int, locale: String) -> String

/// Format a whole number with the locale's digit grouping.
///
/// # Example
/// ```gleam
/// assert format_int(1234567) == "1,234,567"
/// ```
pub fn format_int(value: Int) -> String {
  format_integer(value, locale)
}
