# GitHub-controlled deployment

`Vapor-Server-Root` currently deploys from the VPS by polling `main` with
`vapor-deploy.timer`. GitHub Actions can also trigger the same server-side
deploy service immediately after `main` changes.

The secure target shape is:

1. protect `main`;
2. require PR review/merge for updates;
3. store a dedicated deploy SSH key in GitHub Actions secrets;
4. allow the deploy SSH user to run only `systemctl start/status
   vapor-deploy.service`;
5. keep actual build/deploy authority on the VPS.

This means GitHub Actions does not receive Steam, diagnostics, identity, docs,
or database secrets. It only gets enough SSH authority to ask the VPS to run its
already-installed deployment service.

## Required repository secrets

On `GHF-Studios/Vapor-Server-Root`:

```text
VAPOR_DEPLOY_HOST
VAPOR_DEPLOY_USER
VAPOR_DEPLOY_SSH_KEY
VAPOR_DEPLOY_KNOWN_HOSTS
```

Use the VPS IP while DNS is pending. Replace it with the domain later if
desired.

Optional public smoke-check secret:

```text
VAPOR_DEPLOY_PUBLIC_BASE
```

For the pre-DNS phase this can be:

```text
http://82.165.77.104
```

After DNS/HTTPS cutover, use:

```text
https://vapor.ghf-studios.site
```

When this optional value is present, the workflow runs public health/status
checks after the VPS deploy service completes. These checks intentionally verify
that unauthenticated identity audit/revoke routes return `401`.

## VPS setup

Create an SSH keypair outside the repository. Install only the public key on the
VPS:

```bash
sudo deploy/scripts/install-github-actions-deploy-user.sh \
  --public-key-file /path/to/deploy-key.pub
```

Store the private key as the GitHub secret `VAPOR_DEPLOY_SSH_KEY`.

The restricted deploy user can only start the server-owned deploy service and
show that service's systemd status. GitHub Actions still cannot read
`/etc/vapor-server` secrets, run arbitrary root commands, or directly build
services.

The workflow sequence is:

1. confirm required secrets exist;
2. configure the temporary Actions SSH key;
3. request `vapor-deploy.service` on the VPS;
4. print `vapor-deploy.service` status for diagnostics;
5. optionally run public HTTP smoke checks when `VAPOR_DEPLOY_PUBLIC_BASE` is
   configured.

`systemctl status` can return a non-zero code for a completed oneshot service
that is inactive after successful completion. The workflow therefore treats the
trigger step and public smoke as the pass/fail authority, while the status step
is diagnostic output.

## Current local limitation

At the time this document was written, local `gh auth status` reported an
invalid GitHub CLI token. Branch protection and repository secrets therefore
still need either:

- a repaired local `gh` login with sufficient repository admin permissions; or
- setup through the GitHub web dashboard.
