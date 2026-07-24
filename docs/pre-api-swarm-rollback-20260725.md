# Pre-API-swarm rollback anchor: 2026-07-25

Status: operational safety record for the OpenAI API swarm experiment.

This file records the intended recovery anchor before running any API-funded
agent swarm that may produce large edits. The rollback anchor is the Git tag:

```text
pre-api-swarm-20260725
```

After this document and the current tool/docs changes are committed, that tag
must be created on the resulting `Vapor-Server-Root` commit and pushed to the
remote. The root commit is resolved by the tag rather than embedded here because
embedding a commit's own hash inside the same commit would change the hash.

## Repository commits to preserve

These service repositories were clean and checked before creating this record.

| Repository | Branch | Commit |
| --- | --- | --- |
| `Vapor-Server-Root` | `main` | tag `pre-api-swarm-20260725` |
| `Vapor-Homepage-Server` | `main` | `a41aedc4180792d5561a8e3bf12a1383e172c1ea` |
| `Vapor-Docs-Server` | `main` | `3e1616702a7e41cc35a7a880b756ed06c58d5d13` |
| `Vapor-Identity-Server` | `main` | `ca9e61e5cb39bcf569457603cc23de666e3f6433` |
| `Vapor-Diagnostics-Server` | `main` | `fb318fa0b748d994182174940d51f531e587bf79` |

## Recovery model

If the API swarm goes off the rails, recover from Git history instead of trying
to manually untangle generated edits.

Recommended order:

1. Stop any running swarm process.
2. Inspect the worktree status for the root and service repositories.
3. Save any generated reports you still want to keep outside the repo.
4. Reset the affected repositories back to the preserved commits or tag.
5. Re-run read-only status checks before making new edits.

The rollback commands are intentionally documented rather than automated because
they are destructive to uncommitted local changes.

Root repository rollback target:

```bash
git -C "/home/leslieghf/Documents/GitHub/Loo Cast Repos/Vapor-Server-Root" reset --hard pre-api-swarm-20260725
```

Service repository rollback targets, only if a service repository was changed:

```bash
git -C "/home/leslieghf/Documents/GitHub/Loo Cast Repos/Vapor-Server-Root/Vapor-Homepage-Server" reset --hard a41aedc4180792d5561a8e3bf12a1383e172c1ea
git -C "/home/leslieghf/Documents/GitHub/Loo Cast Repos/Vapor-Server-Root/Vapor-Docs-Server" reset --hard 3e1616702a7e41cc35a7a880b756ed06c58d5d13
git -C "/home/leslieghf/Documents/GitHub/Loo Cast Repos/Vapor-Server-Root/Vapor-Identity-Server" reset --hard ca9e61e5cb39bcf569457603cc23de666e3f6433
git -C "/home/leslieghf/Documents/GitHub/Loo Cast Repos/Vapor-Server-Root/Vapor-Diagnostics-Server" reset --hard fb318fa0b748d994182174940d51f531e587bf79
```

Then restore submodule pointers from the root repository:

```bash
git -C "/home/leslieghf/Documents/GitHub/Loo Cast Repos/Vapor-Server-Root" submodule update --init --recursive
```

## Swarm safety constraints

The swarm should not:

- deploy;
- SSH into the VPS;
- inspect or print secrets;
- commit automatically;
- push automatically;
- reset or delete files automatically;
- treat future services as implemented;
- collapse service/domain authority boundaries.

Human approval is required before applying or committing any swarm-produced
source changes.
