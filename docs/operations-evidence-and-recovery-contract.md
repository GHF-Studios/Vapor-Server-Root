# Operations evidence and recovery contract

Status: source-level contract. Live restore exercises require separate explicit
authorization.

## Purpose

`Vapor-Server-Root` owns composed operational recovery. Individual services own
their own state semantics over time, but root backup/restore remains the
whole-system recovery wrapper for the single-VPS slice.

## State bundle

`deploy/scripts/export-state.sh` writes a gzip tar bundle shaped as:

```text
vapor-server-state/
  manifest.toml
  submodules.txt
  state/
    docs/
    identity/
    diagnostics/
```

The bundle excludes `/etc/vapor-server` and records:

```toml
schema_version = 1
secrets_included = false
```

Backups are recovery bundles, not artifact distribution, not audit storage, and
not a replacement for service-owned export/import formats.

## Restore validation

`deploy/scripts/restore-state.sh` runs
`deploy/scripts/state-bundle-validate.py` before extraction, before stopping
services, and before replacing `/var/lib/vapor-server`.

The validator rejects:

- unreadable or non-gzip tar archives;
- absolute paths;
- parent-directory traversal;
- entries outside `vapor-server-state/`;
- symlinks and hardlinks;
- device nodes, FIFOs, sockets, and unsupported entry types;
- duplicate archive entries;
- bundles without `vapor-server-state/manifest.toml`;
- bundles without `vapor-server-state/state/`;
- unsupported manifest schema versions;
- manifests that do not assert `secrets_included = false`.

The validator does not print archive member contents.

## Restore behavior

Restore remains a root-only operation. It:

1. validates the bundle;
2. takes the deploy/state lock;
3. stops stateful services;
4. extracts into a temporary directory;
5. moves existing state aside under the backup root;
6. installs restored state under `/var/lib/vapor-server`;
7. reapplies expected ownership and restrictive permissions;
8. restarts previously active services;
9. runs the local health check.

This is intentionally not a remote operations API.

## Future work

- Exercise restore on a disposable VPS.
- Add service-owned semantic export/import formats.
- Add restore rehearsal evidence to deployment status only after an actual
  verification run.
- Keep secrets in `/etc/vapor-server`; do not add them to state bundles.
