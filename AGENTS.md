# Agent instructions

This repository owns Vapor server deployment/orchestration. Keep it separate
from `Vapor-Root` application publishing work.

Rules:

- Do not commit secrets, private keys, root passwords, tokens, or VPS-specific
  credentials.
- Keep homepage, docs, identity, and diagnostics as separate service concerns.
- Do not fold service business logic into this root repo.
- Do not populate service submodule worktrees just to edit root orchestration
  metadata.
- Prefer path routing through one public domain.
- Preserve independent rebuild/deploy of each service.
- Preserve whole-system export/import as a composed operation.
- Treat MCP/ACP support as future capability-surface work, not part of the
  initial server MVP.
- Do not introduce Git-backed diagnostics transport.
