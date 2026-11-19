# firefox

## Overview

Firefox: hardware video decode, extensions, and telemetry/new-tab policy.

Extensions are force_installed from AMO's "latest" URL, so they track upstream and cannot be removed in about:addons. Add or drop one here, then rebuild.

## Workarounds

- `default.nix` VA-API prefs: set explicitly because Firefox keeps VA-API opt-in upstream even when system VA-API works.
