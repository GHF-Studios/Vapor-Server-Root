# Vapor server deployment status

Last verified: 2026-07-24 Europe/Berlin.

## Current VPS baseline

- OS: Ubuntu 26.04 LTS.
- Panel: none; Plesk is not used.
- Reverse proxy: Caddy.
- Service manager: systemd.
- Automatic deployment: `vapor-deploy.timer` checks the configured branch.
- GitHub deployment trigger plumbing exists; a restricted VPS deploy user is
  installed, but GitHub repository secrets/branch protection are not configured
  yet.
- Intended public host: `vapor.ghf-studios.site`.
- Temporary pre-DNS access: HTTP fallback may be configured directly against the
  VPS while the domain registration is pending.
- Firewall: UFW enabled with inbound SSH, HTTP, and HTTPS only.
- Deploy root: `/opt/vapor-server-root`.
- State root: `/var/lib/vapor-server`.
- Server-local config: `/etc/vapor-server`.

Secrets are intentionally not recorded here. Admin tokens live only in
server-local env files under `/etc/vapor-server`.

## Verified deployed source

These are the runtime/service commits verified on the VPS. Documentation-only
commits in `Vapor-Server-Root` may be newer than the runtime-impacting commit
recorded here.

```text
Vapor-Server-Root       6926fad
Vapor-Homepage-Server   a41aedc4180792d5561a8e3bf12a1383e172c1ea
Vapor-Docs-Server       27518a45a1916678615620c5047de70296644ffe
Vapor-Identity-Server   ac8dbfb8c5995c881219b786bee7c0005a611a5d
Vapor-Diagnostics-Server 7e08c425ac07bf65ebf16e9c993bf07362f49509
```

## Verified runtime state

- `caddy.service` is active/running.
- `vapor-homepage.service` is active/running.
- `vapor-docs.service` is active/running.
- `vapor-identity.service` is active/running.
- `vapor-diagnostics.service` is active/running.
- `vapor-deploy.timer` is enabled for periodic deployment checks.
- The first timer-triggered `vapor-deploy.service` run completed successfully
  against `main`.
- Restricted deploy-user SSH can trigger `vapor-deploy.service`, and the
  resulting service run reports `success`.
- GitHub Actions deploy workflow no-ops successfully until all deployment
  secrets exist, avoiding failing Actions runs during setup.
- Local health checks return `ok` on ports 7111, 7112, 7113, and 7114.
- Public pre-DNS HTTP health checks pass through the fallback route.
- `/etc/vapor-server/root.env` preserves non-secret deployment settings for
  timer-driven runs, including the temporary pre-DNS HTTP fallback host.
- SSH remains reachable through key authentication after hardening.
- Identity uses SQLite and has been initialized through the local admin-token
  endpoint.
- Identity database files are owned by `vapor:vapor` with restrictive file
  permissions.
- Identity auth readiness endpoint is deployed. GitHub OAuth browser/device
  configuration is present and reports ready. Steam Web API key configuration is
  still missing and Steam ticket verification fails closed until it is set.
- Top-level `/login`, `/logout`, and `/admin` routes are routed to the identity
  service. `/login` is the browser login/register page. `/admin` is publicly
  reachable as a locked shell.
- Identity has Steam-anchored browser profiles through Steam OpenID, GitHub
  browser OAuth linking stubs, GitHub Device Flow/API seams, 5-minute auth
  attempts, and 5-minute dashboard sessions. The dashboard only renders
  privileged identity data/actions when the request carries a non-expired root
  session for a profile with linked Steam and GitHub identities plus the `root`
  role.
- Identity source has been split out of the previous monolithic `main.rs` into
  focused modules for config, route handlers, persistence, provider
  verification, profile/session logic, and shared utilities.
- Identity has a server-local role-grant operator route and script:
  `POST /v1/admin/roles/grant` and
  `deploy/scripts/grant-identity-role.sh`. The route grants `root` or
  `content-developer` only by requiring both external identities: SteamID64 and
  GitHub login. Those identities must already be linked to the same internal
  profile row. The internal profile id is not accepted as grant authority. The
  route accepts either the server-local bootstrap token or a non-expired root
  dashboard session.
- Internal profile ids are not shown in the browser dashboard or protected
  profile listing; they remain database join keys only.
- Public unauthenticated requests to the role-grant route reject with `401`.
- The removed `/v1/admin/root/grant` compatibility route returns `404`.
- `deploy/scripts/configure-identity-auth.sh --status` waits for the identity
  service after restart instead of immediately failing on a bind/readiness race.
- `root` is a role/group on normal Steam-anchored profiles, not a separate
  account type. GitHub does not create standalone player profiles. Effective
  authorization treats `root` as implying `content-developer`.
- The old server-local dashboard password remains present in
  `/etc/vapor-server/identity.env` for compatibility/readiness visibility, but
  it is no longer the dashboard authorization model.
- Temporary HTTP-by-IP identity cookies are explicitly configured with
  `VAPOR_IDENTITY_PUBLIC_ORIGIN=http://82.165.77.104`,
  `VAPOR_IDENTITY_COOKIE_SECURE=false`, and `VAPOR_IDENTITY_COOKIE_PATH=/`.
  Move this to secure HTTPS cookies once DNS is active.
- `deploy/scripts/configure-identity-auth.sh` and
  `deploy/scripts/smoke-identity-auth.sh` are deployed on the VPS.
- Curated Vapor docs are deployed through the public HTTP docs route: 410 files,
  8,739,662 bytes uncompressed, served under `/docs/`.
- A diagnostics smoke run was uploaded and verified to redact obvious secret
  tokens on disk.
- A root-only state export bundle was created under `/var/backups/vapor-server`
  and verified to contain `/var/lib/vapor-server` state plus a manifest, while
  excluding `/etc/vapor-server` env/token files.

## Remaining external dependency

DNS for `vapor.ghf-studios.site` still needs to point at the VPS once the domain
registration is active. Public HTTPS/certificate issuance depends on that DNS
being correct.

The temporary HTTP fallback should be removed after DNS and HTTPS are verified.
