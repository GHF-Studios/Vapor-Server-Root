# Steam identity and publishing authority

Vapor should not treat every Steam proof as the same kind of authority.

## Browser identity

Steam OpenID is the browser login/register path.

Use it for:

- proving the browser user controls a Steam account;
- obtaining the SteamID64;
- creating/resuming the Steam-anchored Vapor player profile.

Do not use it alone for:

- developer publishing rights;
- ownership checks;
- app publishing;
- protected pipeline operations.

## Client/backend identity

Steamworks Web API tickets are the stronger Steam client/backend proof.

Use them for:

- proving a Steam-launched client/session to Vapor backend services;
- developer workflows initiated from Steam/Vapor Shell;
- future ownership checks and app-specific authority checks.

The server verifies those tickets with Steam WebAPI. That path requires
server-local Steam Web API/publisher credentials; those credentials must never
be committed or exposed to clients.

## Vapor roles

Vapor-side roles live on the Steam-anchored profile:

```text
Steam profile
  implicit player
  optional GitHub identity
  optional roles:
    content-developer
    root
```

Policy direction:

- every Steam profile is a player;
- development requires linked GitHub identity;
- root/admin implies development capability;
- root/admin requires Steam + GitHub + `root` role;
- elevated role grants require either the server-local bootstrap token or a
  non-expired root dashboard session, and are rejected unless the provided
  SteamID64 and GitHub login are already linked to the same internal profile
  row;
- Steam-side publishing still needs the corresponding Steamworks/pipeline
  authority.

The internal profile row exists to join Steam identity, GitHub identity, roles,
sessions, and audit events. It is not a user-facing account credential and must
not become the authority developers or admins are asked to reason about.

## Publishing authority

Workshop publishing and app publishing are separate privileged paths.

- Workshop publishing should eventually prove:
  - Steam profile identity;
  - linked GitHub developer identity;
  - Vapor `content-developer` or `root` role;
  - Steamworks/UGC permission for the relevant app/workshop path.
- App/server publishing should require:
  - Steam profile identity;
  - linked GitHub identity;
  - Vapor `root` role;
  - protected deployment/publishing pipeline authority.

The Steam publisher Web API key is not a normal login credential. It belongs on
the server/pipeline side for verification and privileged Steam WebAPI calls.
