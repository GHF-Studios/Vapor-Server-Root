# Cross-service authorization contract

Status: design contract. The transport is not implemented yet.

## Purpose

Identity owns people, linked external identities, sessions, roles, and effective
role evaluation. Other services own their own resource policy.

This contract prevents Docs, Diagnostics, Publishing, Artifacts, Registry,
Toolchain, MCP, or operations tooling from copying the identity database,
inventing parallel roles, or treating a server-local admin token as normal user
authority.

## Authority split

```text
identity proof
  != Vapor role
  != service-local resource permission
  != publishing approval
  != pipeline execution authority
  != Steam publishing credential authority
  != deployment/recovery authority
```

`root` implies `content-developer`, but it does not automatically imply Steam
publishing authority, deploy authority, restore authority, or credential
custody.

## Target shape

The preferred first implementation is audience-bound session introspection:

```text
service receives request
  -> service extracts Vapor identity session proof
  -> service asks Identity to introspect for its audience
  -> Identity returns current identity facts or a generic inactive result
  -> service applies local policy
```

This avoids premature JWT/key-management work while still making Identity the
single source for current session and role facts.

## Introspection request

```json
{
  "audience": "vapor-diagnostics-server"
}
```

Initial audiences:

- `vapor-docs-server`
- `vapor-diagnostics-server`

Future audiences should be named after service authority boundaries, not routes.

## Successful response

```json
{
  "schema_version": 1,
  "active": true,
  "audience": "vapor-diagnostics-server",
  "decision_id": "authz-...",
  "steam_id64": "7656119...",
  "github_login": "example",
  "effective_roles": ["content-developer", "root"],
  "session_class": "steam-openid-browser",
  "session_created_at_unix": 1784930000,
  "expires_at_unix": 1784930300
}
```

The response must not include:

- internal profile IDs;
- session IDs;
- token hashes;
- raw tokens;
- provider tokens;
- Steam tickets;
- database row identifiers.

## Failure behavior

- Missing, invalid, expired, revoked, or disabled sessions return a generic
  inactive/unauthorized result.
- Unsupported audiences fail closed.
- Responses should be `Cache-Control: no-store`.
- The server-local Identity admin token is not an identity session and must not
  be introspectable as a user.

## Downstream service policy

Identity returns facts. It does not decide every resource-specific action.

Initial downstream policies:

| Service action | Required downstream policy |
| --- | --- |
| Docs upload/export | effective `root` plus linked Steam and GitHub, or existing emergency docs token during migration |
| Diagnostics list/download/export | effective `root` plus linked Steam and GitHub, or existing emergency diagnostics token during migration |
| Diagnostics upload | explicit opt-in; identity is optional unless product policy changes |
| Publishing request | Steam profile + linked GitHub + required Vapor role + separate publishing/pipeline authority |

## Migration rule

Docs and Diagnostics may keep their local admin-token scaffolds during the
migration, but those tokens are bootstrap/emergency compatibility paths. They
are not the long-term operator workflow.
