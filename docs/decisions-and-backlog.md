# Vapor server decisions and backlog

This file records server-side decisions and open work that should stay visible
while the implementation is still moving quickly.

## Accepted boundaries

- `Vapor-Server-Root` lives beside `Vapor-Root`; it is not a `Vapor-Root`
  submodule.
- `Vapor-Server-Root` owns deployment/orchestration, shared operations
  conventions, and whole-system export/import composition.
- Homepage, docs, identity, and diagnostics remain separate repositories and
  separate service binaries.
- A single public domain should be sufficient for now, with path routing:
  `/`, `/docs/`, `/api/identity/`, and `/api/diagnostics/`.
- Service dependencies are allowed when they reduce avoidable complexity.
  The initial scaffolds use Axum/Tokio instead of hand-rolled HTTP parsing.
- Diagnostics upload is explicit opt-in only. There is no default/public
  telemetry goal.
- Diagnostics should not collect hostnames or persistent machine identifiers as
  a product requirement. Rough system/platform/spec information is preferable
  when diagnostics context is useful.
- Git is not the normal diagnostics transport and should not be a normal player
  dependency.
- Players should not require GitHub accounts.
- Content/development workflows may require both Steam identity and GitHub
  identity because Vapor content is GitHub-backed for now.
- Identity/auth concerns belong on the identity side. Other services should use
  identity-issued authorization later instead of inventing incompatible auth
  systems.
- Server state must be restorable service-by-service and as a composed whole:
  empty initialization, export, import, and rebuild-from-source are first-class
  operational goals.

## Current scaffold behavior

- Homepage serves public homepage/legal placeholder routes and health.
- Docs serves health, token-protected current-docs upload, and token-protected
  export scaffolds.
- Identity serves health/status plus token-protected init/export scaffolds.
- Diagnostics accepts unauthenticated upload scaffolds and keeps list/download/
  export behind an admin token for now.
- `Vapor-Server-Root` tracks the services as submodules, but the local root
  checkout intentionally does not need populated service worktrees for metadata
  edits.

## Near-term backlog

- Decide the VPS baseline OS and provisioning model.
- Decide the public domain name and final Caddy route configuration.
- Add root-level bootstrap/rebuild scripts once the VPS target is chosen.
- Add systemd unit templates for the four service binaries.
- Define state directory layout and ownership for deployment.
- Define export/import bundle formats for docs, identity, and diagnostics.
- Add docs deployment from a Vapor-owned/root-owned publish workflow.
- Define diagnostics upload request schema, redaction contract, size limits,
  retention policy, and root-dev download/export flow.
- Replace placeholder admin tokens with identity-backed authorization once
  identity is ready enough.
- Add real Steam identity verification using Steam session/auth tickets and
  server-side Steam WebAPI validation.
- Add GitHub Device Flow for developer identity linking.
- Define developer roles, initially at least `root` and `content-developer`.
- Decide how Vapor Shell should wrap server REST APIs without making raw HTTP
  details the normal user workflow.

## Explicitly not current scope

- Full VPS deployment.
- Steam account linking implementation.
- GitHub Device Flow implementation.
- Server-mediated Steam publishing credentials.
- A dashboard or launcher GUI.
- MCP/ACP capability integration.
- Public telemetry.
- Git-backed diagnostics transport.

## Open questions

- Should diagnostics list/download stay strictly root-only from day one, or can
  early pre-alpha tolerate broader temporary access?
- What is the minimal identity model needed before docs and diagnostics should
  consume identity-issued authorization?
- Should docs, diagnostics, and identity state exports be separate files inside
  one root bundle, or one service-owned bundle per service plus a root manifest?
- How much hardware/system information is useful in diagnostics without turning
  the upload into fingerprinting?
- Which parts of this deployment belong in Vapor Shell as operator commands, and
  which should remain server-root-only scripts?
