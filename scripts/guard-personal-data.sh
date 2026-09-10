#!/usr/bin/env bash
# guard-personal-data.sh - fail if curated content leaks identity or secrets.
# Usage: scripts/guard-personal-data.sh
# Scans desktop/, xdg/, profiles/, lib/, bin/, scripts/ and shell/.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN_DIRS=(desktop xdg profiles lib bin scripts shell)
FAIL=0

allowlist() {
  # Returns 0 when the grep match line is an approved provenance/attribution
  # reference rather than leaked personal data.
  local line="$1"
  case "$line" in
    *Copyright*|*ulises-jeremias/dotfiles*|*github.com/ulises-jeremias*|*/home/user/*) return 0 ;;
  esac
  return 1
}

check_pattern() {
  local label="$1" pattern="$2"
  local hits
  hits=$(grep -rniE --exclude-dir=easy-options "$pattern" "${SCAN_DIRS[@]/#/$REPO_ROOT/}" 2>/dev/null || true)
  [[ -z $hits ]] && return 0
  local real=0
  while IFS= read -r line; do
    if ! allowlist "$line"; then
      echo "GUARD-HIT [$label]: $line" >&2
      real=1
    fi
  done <<< "$hits"
  [[ $real -eq 0 ]] && return 0
  FAIL=1
}

cd "$REPO_ROOT"
# Real mailbox strings (a name, an at-sign, a host and a TLD).
# Bare '--email' CLI flags do not match that shape.
check_pattern "email" "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"
# Secret assignments (tokens, passwords, SSIDs, API keys).
check_pattern "secret" "(api[_-]?key|secret|passwd|password|ssid|bearer)[\"']?\s*[:=]\s*[\"']?[^[:space:]\"']+"
# Chezmoi template leftovers must never ship materialized.
check_pattern "chezmoi-var" "\{\{[.-]?\s*(chezmoi|\.gitconfig)"
# Hardcoded personal home trees (the /home/user gtkrc placeholder is allowlisted).
check_pattern "home-path" "/home/[a-z0-9_.-]+/"
# Identity stanzas must not exist in shipped git defaults.
if grep -rn -- "^\[user\]" "$REPO_ROOT/xdg" 2>/dev/null; then
  echo "GUARD-HIT [git-identity]: [user] stanza in xdg/" >&2
  FAIL=1
fi
if grep -rniE -- "user(name|email)" "$REPO_ROOT/xdg/git/config" 2>/dev/null | grep -viE "config\.user|tokens as environment"; then
  echo "GUARD-HIT [git-identity]: userName/userEmail in xdg/git/config" >&2
  FAIL=1
fi

if [[ $FAIL -ne 0 ]]; then
  echo "guard-personal-data: FAIL" >&2
  exit 1
fi
echo "guard-personal-data: OK (no personal data or secret hits)"
