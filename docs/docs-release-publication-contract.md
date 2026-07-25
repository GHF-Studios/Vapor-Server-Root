# Docs release and publication contract

Status: source-level contract. It does not claim the live VPS is already running
this version.

## Purpose

Docs owns accepted documentation releases and the `current` pointer. It does not
own repository checkout, docs generation, generic artifact storage, or
publishing authority.

## State layout

```text
/var/lib/vapor-server/docs/
  releases/
    <release-id>/
      release.toml
      site/
        index.html
        ...
  current.txt
  current/
```

`releases/<release-id>/` is immutable once written. `current.txt` records the
promoted release. `current/` is a materialized compatibility tree so existing
static serving and rollback to older binaries keep working.

## Compatibility upload routes

```text
POST /docs/v1/current
POST /docs/v1/current.tar.gz
```

These routes remain available for existing scripts and smoke checks. They now
create or reuse a content-derived release and then promote it.

Generated release IDs:

```text
legacy-html-<sha256-prefix>
legacy-archive-<sha256-prefix>
```

## Promotion and rollback

```text
POST /docs/v1/releases/<release-id>/promote
```

Promotion verifies that the release contains `release.toml` and
`site/index.html`, atomically replaces `current/`, and atomically updates
`current.txt`.

Rollback is the same operation against an older release. There is intentionally
no separate rollback endpoint.

## Archive validation

Archive publication accepts gzip-compressed tar archives with `index.html` at
the archive root.

The service rejects:

- absolute paths;
- parent-directory traversal;
- duplicate normalized paths;
- symlinks;
- hardlinks;
- device nodes, FIFOs, sockets, and other unsupported entry types;
- archives over the extracted-byte limit;
- archives over the file-count limit.

The HTTP body limit is separate from extracted payload limits.

## Export

`GET /docs/v1/export` returns a release catalog/manifest including the current
release and release metadata. It does not stream full site bodies yet.

Whole payload recovery remains covered by the composed root state bundle until
Docs defines a service-owned streamed export/import format.

## Authority

Docs still uses the service-local admin-token scaffold for protected writes and
export during migration:

```text
Authorization: Bearer <VAPOR_DOCS_ADMIN_TOKEN>
```

The target authority is identity-root authorization or protected pipeline
authority, as defined by `docs/cross-service-authorization-contract.md`.
