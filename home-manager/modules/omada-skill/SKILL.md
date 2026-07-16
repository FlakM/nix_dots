---
name: omada
description: Query, configure, and debug the local TP-Link Omada controller using its official OpenAPI and the omada CLI. Use for Omada sites, access points, switches, clients, adoption, connectivity, configuration, or controller health.
---

# Omada CLI

Use `omada` against `https://omada.house.flakm.com`. It discovers operations from the controller's OpenAPI specification, so do not guess operation names or parameters.

## Prerequisites

The controller must be initialized and an app must exist under **Global View > Settings > Platform Integration > Open API** using client mode. Grant the narrowest role and site privileges needed.

Credentials must come from `OMADA_CLIENT_ID` and `OMADA_CLIENT_SECRET`. Never put the secret in commands, chat, source files, or output. Use `OMADA_BASE_URL=https://omada.house.flakm.com` and `OMADA_SSL_VERIFY=true`.

## Workflow

1. Run `omada auth` to verify access.
2. Run `omada list`, optionally with `--tag`, to find the operation.
3. Run `omada schema <operationId>` before invoking it.
4. Run `omada <operationId>` with parameters derived from the schema.

Prefer read operations. Before create, update, delete, adopt, reboot, upgrade, block, or disconnect operations, explain the impact and obtain user confirmation unless the user explicitly requested that exact mutation.

## Examples

```sh
omada auth
omada list --tag Device
omada schema getGridActiveClients
omada getGridActiveClients
omada getGridKnownClients --page-size 1000 --search-key "printer"
```

Refresh cached metadata after controller upgrades or site changes:

```sh
omada spec refresh
omada sites refresh
```

Use Chrome DevTools against `https://omada.house.flakm.com` when OpenAPI does not expose a UI-only operation or when debugging browser/network behavior.
