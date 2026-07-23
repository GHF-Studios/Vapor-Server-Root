# Vapor server deployment status

Last verified: 2026-07-23 Europe/Berlin.

## Current VPS baseline

- OS: Ubuntu 26.04 LTS.
- Panel: none; Plesk is not used.
- Reverse proxy: Caddy.
- Service manager: systemd.
- Intended public host: `vapor.ghf-studios.site`.
- Deploy root: `/opt/vapor-server-root`.
- State root: `/var/lib/vapor-server`.
- Server-local config: `/etc/vapor-server`.

Secrets are intentionally not recorded here. Admin tokens live only in
server-local env files under `/etc/vapor-server`.

## Verified deployed source

```text
Vapor-Server-Root       9224c18 Tighten VPS service state permissions
Vapor-Homepage-Server   a41aedc4180792d5561a8e3bf12a1383e172c1ea
Vapor-Docs-Server       f969ed4669e1bfa7637cc1f1afb3f61e1f4735a3
Vapor-Identity-Server   08715c4d6f85cf6daa2a24505dd4fa36fa0e404f
Vapor-Diagnostics-Server 7e08c425ac07bf65ebf16e9c993bf07362f49509
```

## Verified runtime state

- `caddy.service` is active/running.
- `vapor-homepage.service` is active/running.
- `vapor-docs.service` is active/running.
- `vapor-identity.service` is active/running.
- `vapor-diagnostics.service` is active/running.
- Local health checks return `ok` on ports 7111, 7112, 7113, and 7114.
- Identity uses SQLite and has been initialized through the local admin-token
  endpoint.
- Identity database files are owned by `vapor:vapor` with restrictive file
  permissions.

## Remaining external dependency

DNS for `vapor.ghf-studios.site` still needs to point at the VPS once the domain
registration is active. Public HTTPS/certificate issuance depends on that DNS
being correct.
