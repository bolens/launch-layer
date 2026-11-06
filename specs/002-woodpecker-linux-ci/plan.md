# Plan

Use two independent native workflows with a shared explicit container-only
entry point and immutable public Node image. Root owns site activation and
required-check cutover. Source scripts reuse Make and hub-pm.sh; no generated
Convex or runtime user configuration changes. Preserve all constitution
requirements by keeping tests on fixtures and no privileged host operations.

## Protected-check handoff

After accepted main `3456fc6` native pipeline 32/8 and Pages publication, move the ordinary
caller's duplicate hosted ShellCheck/Bats work to required native shell/hub
contexts. Keep hosted Python 3.9/Bash 4.3 and both portability platforms, real
editor Docker, supply-chain and Pages checks. Reusable shell defaults remain full;
only this repository's ordinary caller opts out. A new default-false hub input
lets this caller combine its declared-minimum-runtime checks while preserving the
original matrix for other callers. Root adds the two actual native contexts while
preserving strict/admin policy and the existing hosted requirements before merge.
