#!/usr/bin/env bash
# github-token-wizard.sh — per-repo fine-grained PAT setup for private pack repos
#
# Usage: bash scripts/github-token-wizard.sh <remote> [<remote>...]
#        (run from the starter root or scripts/; interactive TTY required)
#
# For each private repo it:
#   1. prints the exact fine-grained token recipe (repo-scoped, contents:read)
#   2. reads the token silently
#   3. VALIDATES it live (git ls-remote) — a wrong-scope/expired token is
#      rejected immediately, not three steps later
#   4. stores it at ~/.config/bot-army/github-tokens/<remote>.token (0600)
#   5. installs a repo-scoped url.insteadOf rewrite so clone/pull refreshes
#      authenticate WITHOUT the token landing in any .git/config
#
# quickstart-default.sh invokes this inline when a private pack is selected
# and no credentials exist (interactive only; non-interactive runs get the
# warning + this command to run separately).

set -u

GIT_ORG="${GIT_ORG:-ergon-automation-labs}"
TOKEN_DIR="$HOME/.config/bot-army/github-tokens"

# --from-file <path> <remote>: non-interactive — the PAT is already staged at
# <path> (host-side, e.g. a file the user wrote locally); this mode reads it,
# validates it live, stores it the same way, installs the same rewrite, and
# NEVER prints the token. Same guarantees as the interactive flow.
if [ "${1:-}" = "--from-file" ]; then
  token_file="${2:-}"
  remote="${3:-}"
  if [ -z "$token_file" ] || [ -z "$remote" ]; then
    echo "Usage: $0 --from-file <path-to-token-file> <remote>   e.g. $0 --from-file ~/pat-ergon_sre.txt ergon_sre" >&2
    exit 1
  fi
  if ! [ -f "$token_file" ]; then
    echo "✗ token file not found: $token_file" >&2
    exit 1
  fi
  token=$(tr -d ' \r\n' < "$token_file")
  if [ -z "$token" ]; then
    echo "✗ token file is empty: $token_file" >&2
    exit 1
  fi
  mkdir -p "$TOKEN_DIR"
  chmod 700 "$TOKEN_DIR"
  if git ls-remote --heads "https://oauth2:${token}@github.com/${GIT_ORG}/${remote}.git" HEAD >/dev/null 2>&1; then
    tokfile="$TOKEN_DIR/${remote}.token"
    printf '%s' "$token" > "$tokfile"
    chmod 600 "$tokfile"
    git config --global --replace-all \
      "url.https://oauth2:${token}@github.com/${GIT_ORG}/${remote}.git.insteadOf" \
      "https://github.com/${GIT_ORG}/${remote}.git"
    chmod 600 "$HOME/.gitconfig" 2>/dev/null || true
    echo "✓ ${remote}: token validated from ${token_file}, stored (0600), refresh rewrite installed"
    exit 0
  else
    echo "✗ token REJECTED for ${remote} (wrong scope, wrong repo, or expired)." >&2
    echo "  Re-check: Only select repositories → ${GIT_ORG}/${remote}, Contents: Read-only." >&2
    exit 1
  fi
fi

if ! [ -t 0 ]; then
  echo "✗ github-token-wizard needs an interactive terminal (TTY)." >&2
  echo "  Run it inside an interactive 'vagrant ssh' session:" >&2
  echo "    bash scripts/github-token-wizard.sh <remote> ..." >&2
  exit 1
fi

if [ $# -eq 0 ]; then
  echo "Usage: $0 <remote> [<remote>...]   e.g. $0 ergon_sre" >&2
  echo "       $0 --from-file <path-to-token-file> <remote>  (non-interactive)" >&2
  exit 1
fi

mkdir -p "$TOKEN_DIR"
chmod 700 "$TOKEN_DIR"

mask() { sed -e "s/oauth2:[^@]*@/oauth2:***@/g" -e "s#https://[a-zA-Z0-9_]*@github.com#https://***@github.com#g"; }

for remote in "$@"; do
  echo ""
  echo "🔐 Private repo: ${GIT_ORG}/${remote}"
  echo "   Create a FINE-GRAINED token scoped to just this repo:"
  echo "   1. open: https://github.com/settings/personal-access-tokens/new"
  echo "   2. Repository access → 'Only select repositories' → ${GIT_ORG}/${remote}"
  echo "   3. Permissions → Repository permissions → Contents: Read-only"
  echo "      (that is all cloning needs — nothing else, no account perms)"
  echo "   4. Generate, copy the token (github_pat_...), paste below."
  echo ""

  tokfile="$TOKEN_DIR/${remote}.token"

  attempts=0
  while [ $attempts -lt 3 ]; do
    attempts=$((attempts + 1))
    printf "   Paste token for %s (input hidden, empty = skip): " "$remote"
    IFS= read -rs token
    echo ""
    token=$(printf '%s' "$token" | tr -d ' \r\n')

    if [ -z "$token" ]; then
      echo "   ⏭  skipped $remote (no token entered)" >&2
      continue 2
    fi

    # Validate live against the exact repo — scope and access proven now.
    if git ls-remote --heads "https://oauth2:${token}@github.com/${GIT_ORG}/${remote}.git" HEAD >/dev/null 2>&1; then
      printf '%s' "$token" > "$tokfile"
      chmod 600 "$tokfile"
      # Repo-scoped rewrite so future clone/pull use the token; the token
      # lives in ~/.gitconfig (repo-scoped), never in any .git/config.
      git config --global --replace-all \
        "url.https://oauth2:${token}@github.com/${GIT_ORG}/${remote}.git.insteadOf" \
        "https://github.com/${GIT_ORG}/${remote}.git"
      chmod 600 "$HOME/.gitconfig" 2>/dev/null || true
      echo "   ✓ ${remote}: token validated, stored (0600), refresh rewrite installed"
      break
    else
      echo "   ✗ token REJECTED for ${remote} (wrong scope, wrong repo, or expired)." >&2
      echo "     Re-check: Only select repositories → ${GIT_ORG}/${remote}, Contents: Read-only." >&2
      [ $attempts -lt 3 ] && echo "     Try again (${attempts}/3)." >&2
    fi
  done

  if [ $attempts -ge 3 ] && ! git ls-remote --heads "https://oauth2:$(cat "$tokfile" 2>/dev/null)@github.com/${GIT_ORG}/${remote}.git" HEAD >/dev/null 2>&1; then
    echo "   ⚠ ${remote}: no working token after 3 attempts — clone will fail;" >&2
    echo "     re-run this wizard or seed the clone manually." >&2
  fi
done

echo ""
echo "Done. Tokens live in $TOKEN_DIR (0600, per-repo, never in git metadata)."