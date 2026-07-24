# Vapor publish and pipeline authority model

Status: speculative contract. This is not implemented by the current deployed
Vapor server slice.

This document defines the intended authority boundary for future
`Vapor-Publish-Server` and `Vapor-Pipeline-Server` work. It builds on the
current documented state:

- `Vapor-Identity-Server` owns Steam identity, GitHub identity, Vapor roles,
  sessions, and authorization facts.
- `Vapor-Server-Root` owns deployment/orchestration, Caddy/systemd wiring, and
  composed export/import.
- Steam browser identity, Steamworks/WebAPI verification, Vapor roles, and
  publishing authority are separate layers.
- Publishing authority is currently conceptual only; there is no protected
  publish pipeline yet.

Do not treat this document as permission to add server-mediated Steam publishing
credentials to the current MVP. The first implementation should validate the
authority model with dry-run/package jobs before real Workshop publishing.

## Recommendation

Use separate service names from the start:

```text
Vapor-Publish-Server   public/control-plane authority and job API
Vapor-Pipeline-Server  protected execution plane / runner
```

They may initially live in one repository with two binaries and two systemd
units if that reduces setup cost. They should not be one public process that
both accepts developer requests and holds Steam/Workshop publishing credentials.

The important first boundary is not repository count. The important first
boundary is authority:

```text
developer/root request
  -> identity verification
  -> publish policy decision
  -> signed immutable job envelope
  -> protected runner execution
  -> logs/artifacts/receipts
```

## Proposed boundary

### Vapor-Publish-Server

`Vapor-Publish-Server` is the public/control-plane service for publishing
intent.

It owns:

- accepting publish requests from future Vapor Shell, CLI, dashboard, or other
  approved clients;
- validating the requester through identity-issued proof or identity service
  introspection;
- checking linked Steam identity, linked GitHub identity, and Vapor role
  requirements;
- applying Vapor publish policy for target/action/source combinations;
- creating immutable publish job records;
- signing canonical publish job envelopes for the pipeline;
- tracking job status, approvals, cancellation, audit events, and artifact
  metadata;
- exposing root/developer-facing job history and receipt APIs.

It does not own:

- Steam/Workshop publishing credentials;
- isolated build or publish execution;
- generic CI;
- GitHub account linking;
- Vapor role grants/revokes;
- docs artifact serving;
- diagnostics upload/list/download;
- VPS deployment orchestration.

### Vapor-Pipeline-Server

`Vapor-Pipeline-Server` is the protected execution plane. It may be implemented
as a local-only service, a runner binary, or a worker loop owned by a dedicated
systemd unit.

It owns:

- accepting only signed jobs produced by `Vapor-Publish-Server`;
- verifying the job signature, expiry, nonce/replay guard, and policy version;
- resolving source by pinned commit or content hash;
- running known pipeline phases in isolated workspaces;
- producing redacted logs;
- producing build/package artifacts;
- injecting Steam/Workshop publishing credentials only into the final
  credentialed phase;
- recording execution receipts and artifact hashes.

It does not own:

- user login;
- GitHub linking;
- Vapor role decisions;
- dashboard sessions;
- public developer authorization;
- role grants/revokes;
- public arbitrary job submission.

## Authority layers

Publishing should require a chain of independently understandable authority
checks. No single external proof should imply full publishing authority.

| Layer | Authority source | Contract |
| --- | --- | --- |
| Local request | Vapor Shell, CLI, browser dashboard, or future tool | Starts intent only; not trusted as authority by itself. |
| Steam identity | Identity-verified Steam profile | Confirms the actor is tied to a Steam-anchored Vapor profile. |
| Strong Steam proof | Steamworks Web API ticket | Preferred for developer/publish-grade local client workflows. Browser OpenID alone is insufficient for protected publishing. |
| GitHub identity | Identity-verified linked GitHub account | Confirms the actor's GitHub identity is linked to the same Steam profile. |
| Vapor role | Identity-owned `content-developer` or `root` role | Confirms Vapor-side capability. `root` implies developer capability. |
| Source authority | Publish policy, branch protection, and later GitHub App checks | Confirms the actor/request is allowed to publish from the selected repo/ref. |
| Publish policy | `Vapor-Publish-Server` | Decides whether this actor may create this target/action job. |
| Job signature | Publish signing key | Allows the pipeline to trust this exact immutable job envelope. |
| Runner authority | Pipeline-local verification and allowlist | Allows execution only for signed, known, non-expired job types. |
| Steam credentials | Pipeline-only server-local secret | Allows the final Workshop/publishing operation, but does not authorize the user. |

Steam/Workshop credentials prove that the server can perform a publish action.
They do not prove that the requesting user is allowed to perform that action.
User authority must be decided before the runner receives a credentialed job.

## Local root/developer request

A local request is a request origin, not the authority source.

Expected future origins:

- Vapor Shell command;
- local CLI command;
- root/admin dashboard action;
- future automation explicitly authorized by root policy.

The request should carry or obtain an identity proof from
`Vapor-Identity-Server`. The current identity service does not yet expose a
mature cross-service JWT/introspection contract, so publish implementation
should not jump ahead by inventing an incompatible auth system.

Near-term acceptable direction:

- publish routes reject unauthenticated requests;
- identity remains the sole owner of Steam/GitHub/profile/role state;
- publish records an actor snapshot from identity facts;
- server-local bootstrap/admin tokens remain emergency/operator tools, not the
  normal developer publish path.

## Identity verification

Publishing should distinguish these identity proofs:

- Steam OpenID browser login: acceptable for browser profile creation and admin
  dashboard shell access, but not sufficient alone for protected publishing.
- Steamworks Web API ticket: preferred proof for local developer workflows
  initiated from Steam/Vapor Shell.
- GitHub OAuth/Device Flow: acceptable only after the identity service verifies
  the GitHub account and links it to the same Steam-anchored profile.

`Vapor-Publish-Server` should not accept raw `steam_id64`, raw `github_login`,
or internal profile ids as publish authority. It may store those values as an
auditable actor snapshot after they are verified by identity.

## Linked GitHub verification

Developer/content publishing is GitHub-backed for now, so linked GitHub identity
is required for developer publish jobs.

The minimum publish-side rule is:

```text
Steam profile identity
  + linked GitHub identity on the same profile
  + effective Vapor developer/root role
  -> eligible to request developer publish jobs
```

Do not treat a GitHub username in a request body as proof. The username/login is
only display/audit data after identity has verified it.

Later source-specific checks may require a GitHub App or server-side GitHub API
verification for repository permission, branch protection status, commit
signature, release provenance, or workflow status. That is a future policy
layer, not part of the current deployed slice.

## Vapor role verification

Initial capability split:

| Capability | Required Vapor role |
| --- | --- |
| Create dry-run/package job for own/developer content | `content-developer` or `root` |
| Create Workshop publish job | `content-developer` or `root`, plus future Steam/UGC target policy |
| Publish/promote app/server infrastructure | `root` |
| Manage publish policy/targets | `root` |
| View global publish audit | `root` |
| View own publish jobs/artifacts | `content-developer` or `root`, subject to target policy |

Role facts come from `Vapor-Identity-Server`. Publish may cache a snapshot on
each job for auditability, but identity remains the source of truth.

## Signed publish job creation

`Vapor-Publish-Server` should create immutable job records after policy approval.
The pipeline should execute signed job envelopes, not arbitrary submitted shell.

Prefer asymmetric signing:

- Publish owns the private signing key or signing-key reference.
- Pipeline owns only the trusted public verification key.
- The signed payload is canonicalized before signing.
- Key id and policy version are included in the envelope.

Minimum envelope fields:

```text
job_id
job_kind
created_at_unix
expires_at_unix
nonce
actor_steam_id64
actor_github_id
actor_github_login
actor_effective_roles
source_kind
source_repo
source_commit
source_artifact_hashes
target_kind
target_app_id
target_workshop_item_id
target_channel
requested_action
policy_version
publish_server_id
signing_key_id
```

The runner should reject jobs when:

- the signature is invalid;
- the signing key is unknown or revoked;
- the envelope is expired;
- the nonce/job id was already consumed incompatibly;
- the job kind is unknown;
- the target/action is outside the runner allowlist;
- the source cannot be resolved to the exact commit/hash in the envelope.

## Protected runner execution

Pipeline execution should be constrained before it becomes powerful.

Initial runner rules:

- local-only bind by default;
- dedicated Unix user;
- no public browser/API surface;
- no arbitrary command submitted by requesters;
- allowlisted job kinds and phase definitions;
- per-job isolated temporary workspace;
- clean environment by default;
- explicit artifact output directory;
- redacted logs;
- resource/time limits;
- explicit final receipt.

Pipeline phases should be separable:

```text
verify envelope
fetch exact source/artifact
prepare isolated workspace
build/package
validate package
publish or dry-run publish
collect logs/artifacts/receipt
```

Build/package phases should not receive Steam/Workshop credentials. Only the
final credentialed publish phase should receive those secrets.

## Steam/Workshop credential isolation

Steam/Workshop publishing credentials belong on the protected pipeline side, not
in identity and not in the public publish service.

Recommended placement:

```text
/etc/vapor-server/pipeline.env
```

or a narrower server-local credential helper. In either case:

- credentials are never committed;
- credentials are never exported in state bundles;
- credentials are not readable by the publish service;
- credentials are not available to normal build steps;
- logs redact credential-like values and command lines that may expose them;
- artifact bundles do not include environment files, config files, cookies, or
  Steam session material.

First implementation should not add real Steam publishing credentials. Start
with dry-run/package jobs and a fake publish receipt shape.

## Route/API implications

Proposed public route:

```text
/api/publish/
```

Initial public API shape:

```text
GET  /api/publish/v1/status
POST /api/publish/v1/jobs
GET  /api/publish/v1/jobs
GET  /api/publish/v1/jobs/{job_id}
POST /api/publish/v1/jobs/{job_id}/cancel
GET  /api/publish/v1/jobs/{job_id}/artifacts
GET  /api/publish/v1/audit
```

Possible later root-only API shape:

```text
POST /api/publish/v1/jobs/{job_id}/approve
POST /api/publish/v1/policies
GET  /api/publish/v1/policies
POST /api/publish/v1/targets
GET  /api/publish/v1/targets
```

Pipeline should not need a public route at first. If an internal HTTP API is
used, bind it locally:

```text
127.0.0.1:<pipeline-port>/v1/status
127.0.0.1:<pipeline-port>/v1/jobs/claim
POST 127.0.0.1:<pipeline-port>/v1/jobs/{job_id}/events
```

The public Caddy route map should include publish only after the auth contract
is explicit. Do not expose a public `/api/pipeline/` route by default.

## State implications

Suggested future state layout:

```text
/var/lib/vapor-server/publish
  publish.sqlite3
  job-envelopes/
  audit/
  artifact-index/

/var/lib/vapor-server/pipeline
  pipeline.sqlite3
  work/
  logs/
  artifacts/
  receipts/

/etc/vapor-server/publish.env
  service config
  publish signing key reference or private key

/etc/vapor-server/pipeline.env
  runner config
  Steam/Workshop credentials
  optional source-fetch credentials
```

Export/import expectations:

- include publish job records;
- include signed job envelopes;
- include logs after redaction;
- include artifacts or a manifest pointing to artifact storage;
- include receipts;
- exclude `/etc/vapor-server`;
- exclude all provider secrets, Steam credentials, GitHub tokens, cookies, and
  private signing material.

If publish and pipeline use SQLite initially, they need the same seriousness as
identity: migrations, restrictive permissions, WAL mode where appropriate, and
documented restore behavior.

## Audit and artifacts

Keep identity audit, publish audit, and pipeline execution records distinct.

Identity audit records:

- login/session/auth attempts;
- Steam/GitHub linking;
- role grants/revokes.

Publish audit records:

- job requested;
- actor identity snapshot;
- source repo/ref/commit;
- target and requested action;
- policy decision;
- approval/cancellation;
- signed envelope hash;
- final status;
- artifact hashes;
- runner receipt id.

Pipeline records:

- job accepted/rejected;
- signature verification result;
- source fetch result;
- build/package phases;
- publish/dry-run phase;
- redacted error summary;
- artifact output;
- final receipt.

Operator-facing audit output should identify actors by linked external
identities, not by internal profile ids as authority.

Artifacts should be immutable after publication. Mutable labels such as
`latest`, `current`, or `candidate` should point at immutable artifact ids, not
replace the artifact body in place.

## Risks

- A combined public publish/runner service can turn a web auth bug into direct
  credential exposure.
- Steam OpenID alone is too weak for protected publishing.
- Raw GitHub login strings are not proof of linked developer identity.
- Mutable branches/tags create time-of-check/time-of-use risk; jobs must pin
  commits or content hashes.
- Runner replay is possible without signed nonce, expiry, and consumed-job
  tracking.
- Build logs can leak secrets if publish credentials enter the general build
  environment.
- A generic CI runner will expand the security boundary too quickly.
- Identity can become overloaded if publish policy is pushed into it; identity
  should provide identity/role facts, while publish owns publish policy.
- GitHub webhooks or branch protection are useful signals, but they are not
  sufficient Vapor publishing authority by themselves.

## What should not be built yet

Do not build yet:

- real server-mediated Steam/Workshop publishing credentials;
- a public pipeline API;
- arbitrary user-submitted runner commands;
- generic CI/CD;
- remote/distributed runners;
- GitHub token storage for broad repo access;
- automatic publish-on-main behavior;
- app/server deployment publishing;
- MCP/ACP publishing capability surfaces.

The safe first step is an authority-model dry run, not live publishing.

## Recommended next concrete step

Implement only a dry-run publish vertical slice after the cross-service auth
contract is explicit:

1. Add `Vapor-Publish-Server` as a minimal service boundary.
2. Expose `GET /api/publish/v1/status`.
3. Define the canonical signed job envelope type.
4. Create a root/developer-authenticated dry-run `POST /api/publish/v1/jobs`
   path.
5. Store the job, actor snapshot, policy decision, and envelope hash under
   `/var/lib/vapor-server/publish`.
6. Add a local-only runner stub that verifies the envelope and writes a fake
   receipt/artifact record.
7. Export/import publish dry-run state without exporting secrets.

Only after that dry-run path is boring should Steam/Workshop credential handling
be designed and reviewed as a separate implementation step.
