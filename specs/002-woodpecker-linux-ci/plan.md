# Plan

Use two independent native workflows with a shared explicit container-only
entry point and immutable public Node image. Root owns site activation and
required-check cutover. Source scripts reuse Make and hub-pm.sh; no generated
Convex or runtime user configuration changes. Preserve all constitution
requirements by keeping tests on fixtures and no privileged host operations.
