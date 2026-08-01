#!/usr/bin/env bash
# Shared resolver for skill-activation marker root (single lattice plugin tree).
#
# Priority:
#   1. ACTIVATED_SKILLS_ROOT — tests / explicit override
#   2. $XDG_RUNTIME_DIR/activated-skills — per-user runtime dir (preferred)
#   3. ${TMPDIR:-/tmp}/activated-skills-u$(id -u) — uid-namespaced fallback
#
# Never use a world-shared fixed /tmp/activated-skills path: on multi-user hosts
# the first creator owns the dir and others can fail-closed or be DoS'd.
# Recursive cleanup additionally requires a user-owned sentinel. An explicit
# override that already contains unrelated entries is usable for current marker
# writes but is never auto-claimed as a recursive deletion boundary.
ACTIVATED_SKILLS_SENTINEL=".lattice-activated-skills-root"

activated_skills_root() {
  if [[ -n "${ACTIVATED_SKILLS_ROOT:-}" ]]; then
    printf '%s' "$ACTIVATED_SKILLS_ROOT"
    return 0
  fi
  if [[ -n "${XDG_RUNTIME_DIR:-}" && -d "${XDG_RUNTIME_DIR}" && -w "${XDG_RUNTIME_DIR}" ]]; then
    printf '%s' "${XDG_RUNTIME_DIR}/activated-skills"
    return 0
  fi
  printf '%s' "${TMPDIR:-/tmp}/activated-skills-u$(id -u 2>/dev/null || echo 0)"
}

activated_skills_root_is_owned() {
  local root="${1:-}"
  local sentinel expected
  [[ -n "$root" && "$root" != "/" && -d "$root" && ! -L "$root" && -O "$root" ]] || return 1
  sentinel="${root}/${ACTIVATED_SKILLS_SENTINEL}"
  [[ -f "$sentinel" && ! -L "$sentinel" && -O "$sentinel" ]] || return 1
  expected="lattice-activated-skills-root-v1 uid=$(id -u 2>/dev/null || echo 0)"
  [[ "$(cat "$sentinel" 2>/dev/null)" == "$expected" ]]
}

activated_skills_prepare_root() {
  local root="${1:-}"
  local sentinel can_claim=0
  [[ -n "$root" && "$root" != "/" ]] || return 1
  # Close the check-then-mkdir race: mkdir -p first (a no-op when the dir
  # already exists), then verify the result. A symlink planted between a
  # would-be existence check and the mkdir makes mkdir -p succeed through it,
  # but the verify-after step below rejects any symlinked, non-directory, or
  # foreign-owned result before anything is written under it.
  (umask 077 && mkdir -p "$root") 2>/dev/null || true
  [[ -d "$root" && ! -L "$root" && -O "$root" ]] || return 1

  sentinel="${root}/${ACTIVATED_SKILLS_SENTINEL}"
  if [[ -e "$sentinel" ]]; then
    activated_skills_root_is_owned "$root"
    return
  fi

  # Claim as a recursive-GC boundary only for default (non-override) roots or
  # an override that is still empty — never auto-claim a nonempty override.
  if [[ -z "${ACTIVATED_SKILLS_ROOT:-}" ]]; then
    can_claim=1
  elif [[ -z "$(find "$root" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    can_claim=1
  fi
  if [[ "$can_claim" -eq 1 ]]; then
    printf 'lattice-activated-skills-root-v1 uid=%s\n' "$(id -u 2>/dev/null || echo 0)" >"$sentinel" || return 1
    chmod 600 "$sentinel" 2>/dev/null || true
    activated_skills_root_is_owned "$root" || return 1
  fi
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  activated_skills_root
  printf '\n'
fi
