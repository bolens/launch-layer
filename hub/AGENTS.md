# Hub guidance

[Documentation](../docs/README.md) maps architecture, deployment, state, and document ownership.

Follow the root [AGENTS.md](../AGENTS.md), [.specify/memory/constitution.md](../.specify/memory/constitution.md), and
[.specify/memory/project-guide.md](../.specify/memory/project-guide.md) as well as these hub-specific rules.

- The hub uses TypeScript and Convex. Read the affected schema, server function,
  and test before editing. Keep the hub contract compatible with the Bash client.
- Validate untrusted client payloads at the server boundary. Preserve existing
  authorization, input bounds, and error behavior.
- Use the package manager wrapper from the repository root:
  `bash scripts/hub-pm.sh lint` and `bash scripts/hub-pm.sh test`.
- Keep tests isolated from production data and credentials. Do not deploy,
  import data, or change remote configuration during local validation.
- Do not hand-edit `convex/_generated/`. When generated Convex AI guidance is
  available locally, read it before changing Convex-specific API behavior.
  Generated guidance complements the tracked project instructions.
- Update schema, functions, clients, tests, and relevant docs together when
  changing a public contract. Report required generation or deployment work
  separately from completed source checks.
