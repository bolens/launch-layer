# Hub database

[Documentation](../docs/README.md) · [Hub guidance](AGENTS.md) ·
[Architecture](../docs/architecture.md) · [Delivery](../RELEASING.md)

The optional hub uses Convex. The Bash launcher keeps local configuration and
caches independently, so installing or rolling back the launcher does not migrate
or restore hub data.

## Ownership and compatibility

[convex/schema.ts](convex/schema.ts) owns document validators, relationships, and
indexes. Read the affected [server functions](convex/) with that schema. Generated
bindings under `convex/_generated/` are outputs, not editable definitions.

Machine records identify fingerprints. Shared configurations reference those
machines, and history records reference configurations. Rate-limit buckets and
download-deduplication records support request accounting. Follow the schema for
exact fields and indexes instead of maintaining a second schema table here.

A field or validator change must account for existing documents and Bash clients.
Describe whether older records remain readable, whether clients can omit the new
field, and whether a backfill is needed. Keep schema, functions, clients, generated
bindings, and tests aligned. Schema validation alone does not establish request
authorization or acceptable disclosure of a fingerprint.

## Data handling and recovery

Fingerprints, configuration text, labels, and notes can disclose user environment
information. Use synthetic records and isolated deployments for validation. Never
copy production data, tokens, or private keys into repository fixtures.

No repository-owned migration or backup runbook is established by this guide.
Before an operational schema change, record the target deployment, a verified
export/restore procedure, compatibility with retained documents, and the rollback
order for server and clients. Do not assume redeploying older code reverses data
writes. Deployment and data import require their own operational authorization.
