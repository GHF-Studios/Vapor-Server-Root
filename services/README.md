# Services

This directory is intended to contain service submodules:

```text
homepage/      -> Vapor-Homepage-Server
docs/          -> Vapor-Docs-Server
identity/      -> Vapor-Identity-Server
diagnostics/   -> Vapor-Diagnostics-Server
```

The service repositories are tracked as submodules. The authoritative local
workspace shape is to work on them here under `Vapor-Server-Root/services/`,
not as separate sibling checkouts beside `Vapor-Server-Root`.
