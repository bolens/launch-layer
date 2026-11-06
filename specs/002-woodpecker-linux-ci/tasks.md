# Acceptance tasks

- [x] Verify syntax, existing local gates and independent source review.
- [x] Observe exact-head native PR and required hosted checks (PR77 at4517095, native32/3 and hosted gates passed).
- [x] Protected squash merge and observe genuine main checks (corrected main `3456fc6` and native pipeline 32/8).

Final run identities and merge SHAs belong in the PR/coordinator receipt.

## Corrective acceptance

The first genuine main shell run exposed doctor tests reading the runner's
`vm.max_map_count`; the two CI runners have different legitimate host values.

- [x] Reproduce the low-limit failure with an owned read-only command fixture.
- [x] Isolate healthy integration fixtures, reject fixture writes, and retain low-limit unit assertions.
- [x] Pass the full164 integration suite and focused doctor tests locally.
- [x] Verify corrected final-head native shell and hub pipelines and retained hosted requirements (PR #78 at `031d1ac`, native pipeline 32/6).
- [x] Merge normally and observe both genuine-main native workflows plus Pages deployment (main `3456fc6`, native pipeline 32/8 and successful targeted Pages recovery).

## Handoff acceptance

- [x] Preserve external reusable defaults and retained minimum/platform checks in source; validate the caller contract locally.
- [ ] Pass final-head native and retained hosted checks for the handoff candidate.
- [ ] Verify Root's additive native-check policy preserves existing protections.
- [ ] Merge normally and verify native main plus Pages publication.
