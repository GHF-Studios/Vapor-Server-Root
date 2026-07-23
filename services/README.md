# Services

This directory is intended to contain service submodules:

```text
homepage/      -> Vapor-Homepage-Server
docs/          -> Vapor-Docs-Server
identity/      -> Vapor-Identity-Server
diagnostics/   -> Vapor-Diagnostics-Server
```

The service repositories are tracked as submodules. Local root checkouts may
leave these submodule worktrees deinitialized when only orchestration metadata is
being edited; the authoritative service work normally happens in the sibling
service repositories.
