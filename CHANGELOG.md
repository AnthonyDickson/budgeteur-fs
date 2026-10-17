# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- A **Log out** button in the header and the phone menu.
- The optional `Oidc__LogoutUrl` setting, the provider's logout page, so logging
  out ends the provider session too. For Authelia, set it to its `/logout` page.
- A signed out page, where logging out ends when `Oidc__LogoutUrl` is not set.
- Signing in after the session expires returns to the page you were on, rather
  than the dashboard.
- The browser title names the page, e.g. "Transactions | Budgeteur".
- Amount fields accept thousands separators and a leading dollar sign, e.g.
  "$1,234.56".
- README instructions for running and using Budgeteur, with screenshots.

### Changed

- `/logout` accepts only `POST`, so another site cannot log you out with a link.
- Validation errors list one problem per line, without the "Validation failed:"
  prefix.

### Fixed

- Date validation messages contained a stray backslash and indentation, e.g. "is
  in the future. \ The latest accepted date is".
- The record value, record balance, and close dialogs focused their help button
  instead of their first field.

## [1.0.0-rc1] - 2026-10-17

The first release candidate.

[Unreleased]: https://github.com/AnthonyDickson/budgeteur-fs/compare/1.0.0-rc1...HEAD
[1.0.0-rc1]: https://github.com/AnthonyDickson/budgeteur-fs/tree/1.0.0-rc1
