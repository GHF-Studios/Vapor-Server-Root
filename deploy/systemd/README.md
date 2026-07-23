# systemd

Future unit templates should keep services separate:

```text
vapor-homepage.service
vapor-docs.service
vapor-identity.service
vapor-diagnostics.service
```

The root repo may install/update these units, but each service should remain
independently buildable and restartable.
