# Orchestration patterns (Lattice)

Portable ownership patterns for multi-agent / subagent use inside Lattice skills.

## Rules

1. **One accountable owner per decision surface.** The hosting skill or explicitly delegated owner is responsible for scope, authority, final content, and validation.
2. **Delegate by capability, not actor identity.** Read or write work may be delegated when briefs and touch-sets are bounded, ownership is explicit, and concurrent writers do not overlap.
3. **Default multi-agent pattern = fan-out + merge:**
   - The accountable owner launches workers with **disjoint** briefs.
   - Workers may return findings or write an explicitly assigned artifact/touch-set.
   - The accountable owner reviews and validates the merged result (e.g. one Lattice `rev` with one `outcome`).
4. **External mutations stay authority-bound.** Issue/PR create, merge, close, push, and destructive cleanup may be delegated only when user authority and the exact target are already explicit; the host remains accountable for verifying the result.
5. **Bound nested delegation is allowed.** Avoid unbounded router recursion, duplicate decision owners, or hidden scope expansion; do not ban a better bounded plan merely because it uses another agent.
6. **Lattice-specific:**
   - Review, Spec, ticket, and PR artifacts each retain a single accountable owner and one final decision surface.
   - Parallel durable writes require disjoint files or an explicit single-writer handoff.
   - Never bind a shippable worktree to `rev-` alone.
   - **Review-only** may write on team base; **same-pass** Review + Spec/tickets/new ADR → one shippable workspace first, write all durable L0 there unless an explicit escape is granted.
   - Do **not** say skills “override any preference for parallelism” or forbid delegation categorically.

## When fan-out is appropriate

| OK | Not OK |
| --- | --- |
| Optional parallel axes into **one** Review (security / tests / perf) with one accountable owner | Freeform multi-persona chat with no `rev` / no `outcome` |
| Delegated implementation on disjoint files with host validation | Multiple agents editing the same artifact without ownership |
| Consumer co-installed practice personas **outside** Lattice lifecycle | Making multi-persona review **required** on every ticket |

## Red flags

- Delegation expands external authority or product scope without user support
- Two agents believe they own the same durable artifact or mutation
- Review concluded only in chat transcripts (no `.lattice/reviews/` file)
- Delegated output is accepted without host review or fresh verification

## Non-goals

- Not a mandate to use multi-agent review or delegation
- Not permission to grow the six lifecycle skills
- Hooks remain optional; these rules apply with or without Claude plugins

See `create-review` policy · `skill-anatomy.md`.
