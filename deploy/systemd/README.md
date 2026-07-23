# systemd

```text
vapor-homepage.service
vapor-docs.service
vapor-identity.service
vapor-diagnostics.service
```

The services are installed separately and run as the `vapor` system user. They
read server-local env files from `/etc/vapor-server` and write state under
`/var/lib/vapor-server`.
