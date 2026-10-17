import gleam/uri

pub const login = "/login"

pub const logout = "/logout"

/// The login path, returning to `url`, a path on this site, once logged in.
pub fn login_returning_to(url: String) -> String {
  login <> "?" <> uri.query_to_string([#("returnUrl", url)])
}
