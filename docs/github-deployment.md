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

## VPS setup

Create an SSH keypair outside the repository. Install only the public key on the
VPS:

```bash
sudo deploy/scripts/install-github-actions-deploy-user.sh \
  --public-key-file /path/to/deploy-key.pub
```

Store the private key as the GitHub secret `VAPOR_DEPLOY_SSH_KEY`.

## Current local limitation

At the time this document was written, local `gh auth status` reported an
invalid GitHub CLI token. Branch protection and repository secrets therefore
still need either:

- a repaired local `gh` login with sufficient repository admin permissions; or
- setup through the GitHub web dashboard.
