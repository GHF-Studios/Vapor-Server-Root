# Vapor Server Root

`Vapor-Server-Root` is the deployment and operations root for Vapor's public
web/server surface. It intentionally lives beside `Vapor-Root`; it is not a
submodule of the game/app root.

## Intended service topology

```text
Vapor-Server-Root/
  Vapor-Homepage-Server/      -> Vapor-Homepage-Server
  Vapor-Docs-Server/          -> Vapor-Docs-Server
  Vapor-Identity-Server/      -> Vapor-Identity-Server
  Vapor-Diagnostics-Server/   -> Vapor-Diagnostics-Server

  deploy/
    caddy/
    systemd/
    scripts/

  docs/
    decisions-and-backlog.md

  crates/
    vapor_server_shared/   # optional later
```

The four services should remain independently rebuildable and deployable. This
root repo owns orchestration, not service business logic.

## Single-domain route map

```text
/                         -> homepage
/docs/                    -> docs
/api/identity/            -> identity
/api/diagnostics/         -> diagnostics
```

## State model

- Homepage: expected to remain mostly stateless.
- Docs: owns uploaded/generated docs artifacts and current/version pointers.
- Identity: owns linked Steam/GitHub identities, roles, and auth/session state.
- Diagnostics: owns opt-in diagnostics uploads, indexes, retention metadata,
  and export/import data.

## Restore model

The long-term goal is reproducible rebuild from source plus either:

- explicit empty initialization; or
- import from a previously exported server state bundle.

Each stateful service should eventually support its own export/import. The root
repo composes those into whole-conglomerate export/import.

## Current status

The single-VPS vertical slice is deployed before DNS is ready. Caddy, systemd
service units, automatic branch polling deployment, SQLite-backed identity
state, pre-DNS HTTP fallback routing, health checks, smoke checks, and whole
server file-state export/restore scripts exist and are tracked here.

The service implementations are still early scaffolds and remain owned by their
own repositories. This root repo owns deployment/orchestration, not service
business logic.

See `docs/decisions-and-backlog.md` for the accepted boundaries, pending
decisions, and future/backburner items that should not be lost.

See `docs/deployment-status.md` for the latest recorded VPS deployment status.

See `docs/identity-auth-runbook.md` for Steam/GitHub identity provider
configuration and auth-flow smoke testing.
