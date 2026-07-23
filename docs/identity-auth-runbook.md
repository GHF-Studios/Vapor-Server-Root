# Identity auth runbook

This records the real provider setup and smoke-test path for the current
single-VPS identity service.

## External provider setup

### GitHub

Create either a GitHub OAuth app or GitHub App with Device Flow enabled.

For the current CLI/operator flow, the identity server only needs the app's
client ID. Do not configure or store a client secret for Device Flow unless a
future browser callback flow explicitly needs it.

Suggested initial values before DNS:

```text
Application name: Vapor Identity
Homepage URL: http://82.165.77.104/
Authorization callback URL: http://82.165.77.104/api/identity/v1/auth/github/callback-placeholder
Device Flow: enabled
```

After DNS/HTTPS is live, update the public URLs to:

```text
Homepage URL: https://vapor.ghf-studios.site/
Authorization callback URL: https://vapor.ghf-studios.site/api/identity/v1/auth/github/callback-placeholder
```

The callback route is currently only a registration placeholder; the deployed
flow uses Device Flow.

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
  --prompt-steam-web-api-key \
  --cookie-secure false \
  --cookie-path /api/identity \
  --restart \
  --status
```

Use `--cookie-secure false` only for the temporary HTTP-by-IP phase. Switch to
`--cookie-secure true` after DNS and HTTPS are verified.

The script edits `/etc/vapor-server/identity.env`, keeps file permissions
root-owned/restrictive, restarts `vapor-identity.service` when requested, and
does not print the Steam key.

## Smoke-test the flow

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
- The dashboard has an API/session gate, but not a polished browser login UI.
- `content-developer` role assignment is not exposed through a dedicated admin
  route yet.
- Temporary HTTP-by-IP cookies are not `Secure`. This must change after HTTPS.
