# claim-probes fixtures

`clean/` is a minimal fake repo (lattice home `clean/.lattice`) on which every
built-in probe in `references/probes.md` passes. `planted/<probe-id>/` holds
the files that, copied over a clean tree, make **exactly that probe** fail
(`claim-probes.bats` asserts the failing set is `{probe-id}` and nothing else).

The bats copies `clean/` into a `mktemp -d` tree, overlays one planted
directory, and runs `claim-probes.sh --home <tmp>/.lattice --json`. Nothing
here is executed by the real repo's probes: `validator-codes-cited-exist` and
`retired-paths-absent` pass `--exclude-dir=fixtures`.
