<!-- required: Why, How. recommended: Summary, Scope, Lineage, References. optional: Verification (only if real), Notes.
     Never invent a Test plan checklist; Verification is only for commands/smokes actually run. -->

### Summary

<one line — optional but preferred>

### Why

[Problem / intent — from user, COMMITTED, or Spec. Not fabricated. Self-contained: readable without chat history.]

### Scope

**In this PR**

- …

**Out of this PR** (optional)

- … (defer / other tickets)

### How

- [1–5 approach bullets. No file list. Diff shows implementation.]
- …

### Verification (commands run)

[Only if real work was done — commands run or smoke steps. Omit entirely if nothing to say. Never invent a checklist.]

### Lineage

- Fixes #N   _(one line per delivered ticket; use Refs #N only if intentionally not closing)_
- Spec: spc-N
- Kind: feat
- Priority: P2

<!-- GitHub auto-closes Fixes/Closes/Resolves only when merging into the *default*
     branch. If this PR targets e.g. `dev` while default is `main`, finish-work
     runs close-fixed-issues.sh to close Fixes issues explicitly. -->

### References

[Explicit pointers only — do not paste full documents]

- Issue: #N — <title or one-line>
- Spec: `spc-N` → `.lattice/specs/spc-N-<slug>.md` (or URL)
- Review / design (if any): `rev-YYYYMMDD-HHMMSSZ` → path

### Notes for reviewers

[Optional: migrations, feature flags, follow-ups the user already agreed]

---

<sub>Generated with an AI coding agent</sub>
