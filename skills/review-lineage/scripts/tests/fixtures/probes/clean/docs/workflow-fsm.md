# Workflow FSM

## 2. Execution

### M1 planning

| State → State | Trigger | Owner |
| --- | --- | --- |
| draft → locked | ratify | human |

### M2 execution

| State → State | Trigger | Owner |
| --- | --- | --- |
| queued → in-progress | bind | system |
| in-progress → pr-open | `create-pr` opens the PR | agent |
| pr-open → closed (merged) | merge | human |
| stuck → M1 | re-scope (prose edge, not a status) | human |

### M3 insight

| Edge | Trigger |
| --- | --- |
| closed → queued | (this is an M3 prose table, not M2) |
