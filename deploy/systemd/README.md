# systemd

```text
vapor-homepage.service
vapor-docs.service
vapor-identity.service
vapor-diagnostics.service
vapor-deploy.service
vapor-deploy.timer
vapor-state-export.service
vapor-state-export.timer
```

The app services are installed separately and run as the `vapor` system user.
They read server-local env files from `/etc/vapor-server` and write state under
`/var/lib/vapor-server`.

The deploy and state-export units run as root-owned oneshot operations. They
share `/run/vapor-server-deploy.lock`, so deploy/export/restore operations do
not run concurrently.
