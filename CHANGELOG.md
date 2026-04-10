# Changelog

## 0.3.5

- **View helpers:** `helper_method :current_user` exposes toolbox methods to jb/jbuilder views, same API as `ActionController::Base`. `helper ApplicationHelper` includes a module directly. Both inherit through `ApplicationToolbox`.
- OAuth HTML controllers (consent, authorized apps) inherit from `Toolchest.base_controller` (default: `ApplicationController`). Set to `"ActionController::Base"` to opt out of host app behavior.
- OAuth API controllers (token, metadata, registration) now use `ActionController::API` instead of inheriting from the host's `ApplicationController`.
- Route helper delegation: `_path`/`_url` helpers in engine views fall through to `main_app` so host layouts work without `main_app.` prefixes. Disable with `Toolchest.delegate_route_helpers = false`.

## 0.3.4

- **Security:** Empty-scoped tokens no longer bypass scope filtering when scopes are configured (fail closed).
- **Security:** Authorization code exchange is now atomic — prevents race condition double-minting.
- **Security:** Dynamic client registration rejects redirect URIs containing newlines.

## 0.3.3

- Per-tool scope override: `tool "Move ticket", scope: "admin"` bypasses convention-based scope matching for individual tools. Accepts a string or array of strings (OR — any matching scope grants access). Enforced on both `tools/list` and `tools/call`.

## 0.3.0

- Sampling: `mcp_sample("prompt")` asks the client's LLM to do work from inside a tool action. Block form for full control. Raises `Toolchest::Error` if the client doesn't support it (rescue with `rescue_from`).
- Progress: `mcp_progress(n, total: t, message: "...")` reports progress during long-running actions. Clients show a progress bar.
- Annotations: `access: :read` sets `readOnlyHint: true`, `access: :write` sets `destructiveHint: true`. Override with `annotations: { openWorldHint: true }` on the tool macro.

## 0.2.0

- **Breaking:** `auth` now returns `Toolchest::AuthContext` instead of the raw token. Use `auth.resource_owner` for the user, `auth.scopes` for scopes, `auth.token` for the raw record.
- **Breaking:** Requires mcp gem >= 0.10 (was ~> 0.8)
- **Breaking:** Scope filtering fails closed — if scopes can't be determined, no tools are shown (was: show all)
- Optional scopes: `config.optional_scopes = true` adds checkboxes to the consent screen
- Required scopes: `config.required_scopes = [...]` — always granted, can't be unchecked
- Per-user scope gating: `config.allowed_scopes_for { |user, scopes| ... }`
- Consent view no longer ejected on install (use `rails g toolchest:consent` to customize)
- Fix frozen SSE headers crash with Rack middleware

## 0.1.0

Initial release.
