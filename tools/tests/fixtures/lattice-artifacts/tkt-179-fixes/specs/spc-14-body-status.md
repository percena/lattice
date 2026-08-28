# Spec: Body prose status scoping

> **TL;DR:** A spec without front matter must not have its status read from body prose.
> **Kind:** feat · **Status:** locked · **Mode:** C · **Priority:** P2

## Notes

The following line is body prose, not front matter:

status: bogus

The old full-text regex would match it; the new parse_front_matter scoping must not.

## Acceptance

- [x] **A1** one
