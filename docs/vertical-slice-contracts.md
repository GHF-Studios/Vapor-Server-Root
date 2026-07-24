# Vapor server vertical-slice contracts

This file describes the current working slice as an explicit set of contracts.
It is intentionally stricter than the current implementation polish: when code
and this document disagree, treat that as a bug or an intentional migration that
must be documented.

## Goal of the current slice

The server stack should prove the full path from public web entrypoint to
service state and back:

```text
browser/Vapor client
  -> one public HTTP(S) origin
  -> Caddy path router
  -> independently owned service binaries
  -> service-owned state under /var/lib/vapor-server
  -> export/import/rebuild operations from Vapor-Server-Root
```

The goal is not a polished production frontend yet. The goal is that every
working behavior has a clear owner, a clear authority model, and a clear upgrade
path.

## Repository ownership

- `Vapor-Server-Root` owns orchestration: Caddy, systemd, deploy scripts,
  bootstrap/hardening, whole-system export/import composition, and operator
  runbooks.
- `Vapor-Homepage-Server` owns public homepage/legal/product pages.
- `Vapor-Docs-Server` owns docs artifact upload, serving, current/version
  pointers, and docs export/import.
- `Vapor-Identity-Server` owns Steam identity, GitHub identity, roles, sessions,
  and authorization decisions.
- `Vapor-Diagnostics-Server` owns opt-in diagnostics uploads, redaction,
  indexes, retention, list/download/export, and diagnostics restore/import.

The root repo may provide shared deployment conventions. It must not absorb
service business logic unless a shared library is deliberately introduced.

## Route map

```text
/                         public homepage
/docs/                    public current docs
/login                    public Steam-anchored login/register
/login/steam              Steam OpenID browser auth
/login/github             GitHub browser link flow after Steam login
/logout                   identity session logout
/admin                    public shell; privileged content requires root session
/admin/roles/grant        browser role-grant form; root session only
/admin/roles/revoke       browser role-revoke form; root session only
/api/identity/            identity service API
/api/diagnostics/         diagnostics service API
```

Every stateful service should expose a public, secret-free `/v1/status` probe
that reports readiness and temporary auth model without leaking tokens.

Temporary pre-DNS HTTP-by-IP access exists only for the current setup phase. The
intended long-lived public origin is `https://vapor.ghf-studios.site`.

## Identity model

- Steam is the Vapor profile anchor.
- GitHub attaches to a Steam-anchored profile for development/root work.
- Players do not need GitHub.
- Developers need Steam + GitHub.
- `root` is a role on a normal Steam-anchored profile.
- `root` implies `content-developer` capability.
- The internal profile row exists to join Steam accounts, GitHub accounts,
  sessions, roles, and audit events. It is not a login credential and should not
  be exposed as the user-facing authority.

## Authorization contract

| Capability | Required authority |
| --- | --- |
| View public homepage/docs | none |
| Upload docs | docs upload token for now; future root/pipeline auth |
| Upload diagnostics | explicit opt-in client upload; future identity-aware policy |
| List/download diagnostics | admin token for now; future root session |
| Create Steam player profile | Steam OpenID browser proof |
| Link GitHub | existing Steam session + GitHub OAuth proof |
| View admin dashboard data | non-expired root dashboard session |
| Grant roles from dashboard | non-expired root dashboard session |
| Revoke roles from dashboard | non-expired root dashboard session; last active root is protected |
| View identity audit events | server-local admin token or non-expired root dashboard session |
| Bootstrap first root | server-local admin token or first-root flow |
| Emergency operator role grant | server-local admin token on the VPS |

Server-local admin tokens are operational bootstrap tools. They should not be
the normal UI or developer workflow after a root profile exists.

## Role-grant contract

Role grants require both external identities:

```json
{"role":"root","steam_id64":"7656119...","github_login":"example"}
```

The server must verify that the SteamID64 and GitHub login are already linked to
the same internal profile row before writing the role. Role grants by internal
profile id are intentionally not supported.

Role revocation uses the same external-identity target shape:

```json
{"role":"root","steam_id64":"7656119...","github_login":"example"}
```

The service refuses to revoke the last active `root` role through normal
operator routes. Since `root` implies `content-developer`, revoking
`content-developer` from an active root profile is rejected; demotion to
developer is represented as explicitly granting `content-developer`, then
revoking `root`.

Audit listings identify actor/subject profiles by linked external identities.
They must not expose internal profile ids as operator-facing authority.

## State contract

```text
/var/lib/vapor-server/homepage       mostly stateless today
/var/lib/vapor-server/docs           docs artifacts and current pointers
/var/lib/vapor-server/identity       SQLite identity DB and session state
/var/lib/vapor-server/diagnostics    uploaded diagnostics and indexes
/etc/vapor-server                    server-local env/secrets; not exported
```

State must be recoverable through:

1. rebuild source from the configured branch;
2. initialize empty service state; or
3. restore a previously exported state bundle.

Whole-system export/import is composed in `Vapor-Server-Root`; service-specific
formats should become explicit service contracts over time.

## Deployment contract

The current deployment path is:

```text
GitHub main branch
  -> VPS /opt/vapor-server-root checkout
  -> submodule update
  -> cargo release build per service
  -> systemd unit install/restart
  -> Caddy config install/restart
  -> local health check
```

The systemd timer polls `main`. GitHub Actions trigger plumbing exists but is
not fully configured as the authority path yet. Server secrets must remain on
the VPS, not in GitHub Actions.

## Smoke-check contract

Minimum checks before claiming the stack is good:

- all four local service health checks pass;
- docs, identity, and diagnostics status probes pass;
- public pre-DNS routes answer while DNS is pending;
- `/api/identity/v1/auth/status` reports configured provider readiness
  accurately;
- unauthenticated role-grant attempts return `401`;
- unauthenticated role-revoke and audit-list attempts return `401`;
- removed legacy routes return `404`;
- profile listings do not expose internal profile ids;
- diagnostics smoke upload redacts obvious secrets;
- docs route serves the current docs bundle;
- state export excludes `/etc/vapor-server` secrets.

## Current wobbly seams

These are not reasons to stop; they are the next places to widen the pipe.

- Admin UI is functional but unstyled and still missing role-change
  confirmation polish.
- Identity sessions are short and server-local; no JWT/service-to-service auth
  contract exists yet.
- Docs and diagnostics still use token/admin-token scaffolds rather than
  identity-root authorization.
- Diagnostics schema, retention, redaction contract, and root download UX need a
  proper contract before broad client integration.
- Restore/import has a root-level file-state path but service-owned import
  formats are not mature.
- Deployment is direct and useful, but branch protection/GitHub trigger secrets
  are not fully configured.
- HTTPS/domain cutover is pending DNS.
- Publishing authority is documented conceptually but not implemented as a
  protected pipeline.
