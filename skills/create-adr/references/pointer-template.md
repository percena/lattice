# ADR template — pointer

The canonical ADR template ships with the **`create-adr`** skill:

`skills/create-adr/references/templates/adr.md`

This file is a **pointer** to that single source of truth. Do not hand-maintain
a second copy here — edits go in the shipped template, and every consumer that
installs the Lattice plugin gets the same template.

## Preferred: use the skill

```
/create-adr
```

The skill allocates the next 3-digit number, copies this template, and appends
the `docs/adr/README.md` index row for you.

## Manual fallback (no skill runtime)

```bash
# 1. Next number = max existing NNN + 1  (manual scan of docs/adr/)
# 2. Copy the shipped template (adjust the plugin path for your install)
cp skills/create-adr/references/templates/adr.md docs/adr/NNN-short-title.md
# 3. Fill Context / Decision / Consequences; set Status
# 4. Append a row to docs/adr/README.md index table by hand
```

---

_Not a Lattice bloodline/graph node. Cite from Spec/PR/Review with `ADR-NNN` or the ADR file path._
