# Requirement coverage

| Requirement | Source and acceptance evidence |
| --- | --- |
| FR-001 | `docs/architecture.md` layer table, shared configuration functions in lib, precedence and traversal Bats fixtures. |
| FR-002 | Shared CLI dispatch/runtime chain and preview/status fixture suites. |
| FR-003 | `lib/commands`, `lib/tui`, shared function contracts and native unit/integration fixtures. |
| FR-004 | `scripts/launchlayer-mcp.py`, adapter protocol/validation/cancellation fixtures; architecture MCP contract. |
| FR-005 | `hub/convex/lib/auth.ts`, auth tests and HTTP route fixtures. |
| FR-006 | `hub/convex/lib/validation.ts`, schema/HTTP/configs and validation/ranking/quota tests. |

## Verification receipt

Native Bash gate passed 884 cases. Hub lint/types, 110 unit tests, and 33 Convex fixture tests passed. Pages, changelog, and workflow checks passed. Separate self-review traced configuration precedence/INCLUDE restrictions, read-only MCP ownership, and Hub auth/input bounds. Tests used local fixtures, not production Hub data.
