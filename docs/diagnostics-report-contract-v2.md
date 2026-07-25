# Diagnostics report contract v2

Status: source-level contract. It does not claim that the live VPS is already
running this version.

## Purpose

Diagnostics are an explicit opt-in support path. They are not telemetry and not
a machine fingerprinting system.

The v2 contract gives the client a structured upload shape while preserving the
legacy v1 text-upload route during migration.

## Upload routes

```text
POST /api/diagnostics/v1/runs
POST /api/diagnostics/v2/reports
```

`POST /v1/runs` accepts legacy plain text and stores it through the same
redaction/storage core as v2.

`POST /v2/reports` accepts JSON:

```json
{
  "schema_version": 2,
  "consent": true,
  "client_version": "local-build-id",
  "platform": {
    "os_family": "linux",
    "arch": "x86_64",
    "memory_mb_bucket": "8192-16383",
    "steam_deck": false
  },
  "artifacts": [
    {
      "name": "vapor.log",
      "content": "text"
    }
  ]
}
```

Allowed artifact names:

- `vapor.log`
- `launcher.log`
- `steps.txt`
- `errors.txt`

Unknown JSON fields are rejected. `consent` must be `true`.

## Privacy boundaries

The schema intentionally has no fields for:

- hostname;
- persistent machine id;
- remote IP;
- account id;
- serial number;
- MAC address;
- installation id.

Useful platform context is coarse: OS family, architecture, Steam Deck yes/no,
and memory bucket.

## Storage contract

Accepted reports are stored under:

```text
runs/
  diag-<unix-milliseconds>-<uuid-v4>/
    metadata.json
    metadata.toml
    vapor.log
```

Raw request bodies are not retained. The stored log is normalized and redacted
before it is written.

`metadata.json` is canonical for v2. `metadata.toml` remains as an
operator-readable compatibility summary.

## Redaction contract

The service redacts common sensitive forms before storage:

- `password=value`
- `password = "value"`
- `token: value`
- `Authorization: Bearer value`
- `Cookie: value`
- sensitive URL query parameters named `token`, `secret`, `password`, `ticket`,
  or `auth`;
- common GitHub token prefixes.

The redaction contract is defensive but not a guarantee that arbitrary sensitive
text can never appear. Clients should avoid sending secrets in the first place.

## Quota contract

`VAPOR_DIAGNOSTICS_MAX_STORED_BYTES` sets a non-secret aggregate storage quota.
The default is 256 MiB. Exceeding the quota rejects the new upload without
deleting existing reports.

Automatic destructive retention is intentionally not part of this contract yet.

## Read/export authority

For now, list/download/export routes remain behind the diagnostics-local
admin-token scaffold:

```text
Authorization: Bearer <VAPOR_DIAGNOSTICS_ADMIN_TOKEN>
```

That token is a bootstrap/emergency mechanism. The target model is identity-root
authorization once the cross-service authorization contract is implemented.
