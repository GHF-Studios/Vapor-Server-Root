# Docs publication contract

Status: source-level contract. It does not claim the live VPS is already
running this version until `docs/deployment-status.md` says so.

## Purpose

Docs owns the currently served documentation tree under `/docs/`.

It does not own repository checkout, docs generation, generic artifact storage,
or publishing authority. If docs ever needs historical releases, provenance, or
rollback labels, that belongs in a later publishing/artifact boundary rather
than in this pre-alpha docs server.

## State layout

```text
/var/lib/vapor-server/docs/
  current/
    index.html
    metadata.toml
    ...
```

`current/` is the single served tree. A successful upload stages a replacement
tree first, validates it, and then atomically replaces `current/`.

## Routes

```text
GET  /docs/healthz
GET  /docs/status
POST /docs/current
POST /docs/current.tar.gz
GET  /docs/export
```

`POST /docs/current` accepts a single HTML document and writes it as
`current/index.html`.

`POST /docs/current.tar.gz` accepts a gzip-compressed tar archive with
`index.html` at the archive root.

## Archive validation

Archive publication rejects:

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

`GET /docs/export` returns the current docs metadata plus the current
`index.html` body. Whole-tree streaming can be added when it becomes necessary.

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
