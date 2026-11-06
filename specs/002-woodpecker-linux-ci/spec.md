# Woodpecker Linux CI

- Run actual repository shell, Pages and hub lint/test/coverage commands for PR
  and main revisions with failures propagated.
- Keep Linux container tests disposable, unprivileged, credential-free and
  bounded; no system tuning, Docker socket or host filesystem mounts.
- Preserve explicit minimum-runtime, macOS and privileged publication gates.
- Observe native exact-head PR and genuine main success before acceptance.
