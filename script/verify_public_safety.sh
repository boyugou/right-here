#!/usr/bin/env bash
#
# Reject anything in tracked files that must not be published: email addresses, developer-machine
# paths, key material and credential files. The repository may become public at any time.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail=0
report() { echo "public-safety: $1" >&2; fail=1; }

files=()
while IFS= read -r f; do files+=("$f"); done < <(git ls-files)
[[ ${#files[@]} -gt 0 ]] || exit 0

# Email addresses. The only allowed @ forms are file-mention examples and git remotes, neither of which matches.
if grep -nE '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z]{2,}' -- "${files[@]}" 2>/dev/null \
  | grep -vE 'git@github\.com|@[0-9]x\.(png|jpg)'; then
  report "email address found"
fi

# Developer-machine home directories (generic example users are fine).
if grep -nE '/Users/[A-Za-z0-9._-]+' -- "${files[@]}" 2>/dev/null \
  | grep -vE '/Users/(tester2?|me|name|user|you|someone|example|o'"'"'brien|x)\b' \
  | grep -vE '^script/verify_public_safety.sh'; then
  report "developer-machine path found"
fi

# Key material and credential files.
if grep -nE 'BEGIN (RSA |EC |OPENSSH |PGP )?PRIVATE KEY|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|sk-[A-Za-z0-9]{32,}' -- "${files[@]}" 2>/dev/null; then
  report "key material found"
fi
for f in "${files[@]}"; do
  case "$f" in
    *.p12|*.p8|*.pem|*.mobileprovision|*.provisionprofile|*/secrets/*|secrets/*|.env|.env.*) report "credential file tracked: $f" ;;
  esac
done

# A signing identity's personal name or team in tracked files.
if grep -nE 'Developer ID (Application|Installer): [A-Z][a-z]+ [A-Z]|Apple (Development|Distribution): [A-Z][a-z]+ [A-Z]' -- "${files[@]}" 2>/dev/null; then
  report "signing identity found"
fi

if [[ "$fail" == 1 ]]; then exit 1; fi
echo "public-safety: ok (${#files[@]} files)"
