# Identity auth runbook

This records the real provider setup and smoke-test path for the current
single-VPS identity service.

## External provider setup

### GitHub

Create either a GitHub OAuth app or GitHub App with Device Flow enabled.

For CLI/operator Device Flow, the identity server only needs the app's client
ID. For browser login/linking, the identity server also needs the app's client
secret stored server-side.

Suggested initial values before DNS:

```text
Application name: Vapor Identity
Homepage URL: http://82.165.77.104/
Authorization callback URL: http://82.165.77.104/login/github/callback
Device Flow: enabled
```

After DNS/HTTPS is live, update the public URLs to:

```text
Homepage URL: https://vapor.ghf-studios.site/
Authorization callback URL: https://vapor.ghf-studios.site/login/github/callback
```

The deployed service supports both GitHub Device Flow and browser callback flow.

### Steam

Create or use the Steam publisher Web API key for AppID `2122620`.

The key must stay server-side. The client obtains a Steam Web API ticket through
Steamworks with identity `vapor-identity`; the server verifies the ticket with
Steam and stores only the verified SteamID64.

## Configure the VPS

Run this on the VPS after the external values exist:

```bash
sudo /opt/vapor-server-root/deploy/scripts/configure-identity-auth.sh \
  --github-client-id <github-client-id> \
  --prompt-github-client-secret \
  --prompt-steam-web-api-key \
  --public-origin http://82.165.77.104 \
  --cookie-secure false \
  --cookie-path / \
  --restart \
  --status
```

Use `--cookie-secure false` only for the temporary HTTP-by-IP phase. Switch to
`--public-origin https://vapor.ghf-studios.site` and `--cookie-secure true`
after DNS and HTTPS are verified.

The script edits `/etc/vapor-server/identity.env`, keeps file permissions
root-owned/restrictive, restarts `vapor-identity.service` when requested, and
does not print the Steam key.

## Smoke-test the flow

Browser login/register:

```text
http://82.165.77.104/login
```

After a Steam profile has signed in and linked GitHub, grant the root role from
the VPS by naming both external identities. The server rejects the grant unless
that SteamID64 and GitHub login are already linked to the same internal profile:

```bash
sudo /opt/vapor-server-root/deploy/scripts/grant-identity-role.sh \
  --role root \
  --steam-id64 <your-steamid64> \
  --github-login <your-github-login>

sudo /opt/vapor-server-root/deploy/scripts/grant-identity-role.sh \
  --role content-developer \
  --steam-id64 <developer-steamid64> \
  --github-login <developer-github-login>
```

The script reads `/etc/vapor-server/identity.env` locally and does not print the
admin token. The server refuses elevated role grants until the target profile
has both linked Steam and GitHub identities. Conceptually, `root` implies
developer capability; a root profile does not need a separate
`content-developer` row unless policy later chooses to store both explicitly.

GitHub-only readiness smoke:

```bash
/opt/vapor-server-root/deploy/scripts/smoke-identity-auth.sh \
  --base http://82.165.77.104/api/identity \
  --no-wait
```

Full root-session smoke requires a real Steam ticket hex from a Steamworks/Vapor
client:

```bash
/opt/vapor-server-root/deploy/scripts/smoke-identity-auth.sh \
  --base http://82.165.77.104/api/identity \
  --steam-ticket-hex <ticket-hex-from-client> \
  --bootstrap-first-root
```

During the GitHub Device Flow step, the script prints the GitHub verification
URL/code and polls until authorization succeeds or the timeout expires. It does
not print provider tokens or dashboard cookies.

## Current intentional limitations

- Steam proof still needs a Steamworks/Vapor client command that can call
  `GetAuthTicketForWebApi` and pass the ticket hex into the smoke/login flow.
- The dashboard has a functional browser login shell, but not a polished UI.
- Role assignment is available through a server-local operator script/API, not
  through public dashboard buttons yet.
- Temporary HTTP-by-IP cookies are not `Secure`. This must change after HTTPS.
