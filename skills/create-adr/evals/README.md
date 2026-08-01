# create-adr evals

`create-adr` is a **doc-tool-domain** skill, not a lifecycle-six skill, so
`evals.json` is not required by `tools/validate-skills.sh`. This directory
holds a dogfood check and will host behavioral cases if the skill gains
lifecycle routing.

## Dogfood check

`check-dogfood.sh` — end-to-end smoke: allocate a number against a throwaway
temp dir shaped like `docs/adr/`, atomically claim the shipped template, and
confirm the README index appender is idempotent. Run after any change to the
scripts or template.

```bash
bash evals/check-dogfood.sh
```

The unit-level correctness of the allocator, claim helper, and appender is covered by
`scripts/tests/*.bats` (run with `bats`).
