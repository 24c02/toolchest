# Changelog

## 0.2.0

- Optional scopes: `config.optional_scopes = true` adds checkboxes to the consent screen
- Required scopes: `config.required_scopes = [...]` — always granted, can't be unchecked
- Per-user scope gating: `config.allowed_scopes_for { |user, scopes| ... }`

## 0.1.0

Initial release.
