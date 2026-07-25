# Diagnostics report contract

Status: current source-level contract. This is pre-alpha and intentionally not a
stable public API promise.

## Purpose

Diagnostics are an explicit opt-in support path. They are not telemetry and not
a machine fingerprinting system.

## Upload route

```text
POST /api/diagnostics/reports
```

Request:

```json
{
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

`metadata.json` is canonical. `metadata.toml` is an operator-readable summary.

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

Automatic destructive retention is not part of the current contract.

## Read/export authority

For now, list/download/export routes remain behind the diagnostics-local
admin-token scaffold:

```text
Authorization: Bearer <VAPOR_DIAGNOSTICS_ADMIN_TOKEN>
```

That token is a bootstrap/emergency mechanism. The target model is identity-root
authorization once the cross-service authorization contract is implemented.
