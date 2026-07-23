# Deployment

`deploy/` contains the reproducible server deployment material for the current
single-VPS vertical slice.

Current baseline:

- Ubuntu 26.04 LTS;
- no Plesk;
- Caddy reverse proxy and HTTPS;
- systemd service units;
- SQLite-backed identity state;
- branch-based source deployment from `Vapor-Server-Root`;
- state under `/var/lib/vapor-server`;
- service env files under `/etc/vapor-server`;
- source checkout under `/opt/vapor-server-root`.

No secrets belong in this repository. The bootstrap script creates server-local
admin tokens in `/etc/vapor-server/*.env` when those files do not already exist.

## First-run outline

After DNS points `vapor.ghf-studios.site` at the VPS:

```bash
sudo deploy/scripts/bootstrap-ubuntu.sh
sudo deploy/scripts/deploy.sh
```

The scripts are intended to be idempotent, but they are still real server
operations: package installation, system user creation, systemd unit
installation, Caddy configuration, source checkout/update, service build, and
service restart.

## Scripts

- `scripts/bootstrap-ubuntu.sh`: install OS packages, create users/directories,
  and create server-local env files.
- `scripts/deploy.sh`: clone/update the root repo, update submodules, build
  services, install units/proxy config, and restart services.
- `scripts/install-systemd.sh`: install/enable the four service units.
- `scripts/install-caddy.sh`: render/install the Caddy config.
- `scripts/health-check.sh`: check local service health endpoints.
