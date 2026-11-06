# Acceptance tasks

- [x] Verify syntax, existing local gates and independent source review.
- [x] Observe exact-head native PR and required hosted checks (PR77 at4517095, native32/3 and hosted gates passed).
- [ ] Protected squash merge and observe genuine main checks.

Final run identities and merge SHAs belong in the PR/coordinator receipt.

## Corrective acceptance

The first genuine main shell run exposed doctor tests reading the runner's
`vm.max_map_count`; Bamboo and Grove have different legitimate host values.

- [x] Reproduce the low-limit failure with an owned read-only command fixture.
- [x] Isolate healthy integration fixtures, reject fixture writes, and retain low-limit unit assertions.
- [x] Pass the full164 integration suite and focused doctor tests locally.
- [ ] Verify corrected final-head native shell and hub pipelines and retained hosted requirements.
- [ ] Merge normally and observe both genuine-main native workflows plus Pages deployment.
