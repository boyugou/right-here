#!/usr/bin/env bash
#
# Reject anything in the repository's files that must not be published: email addresses, developer-machine paths, key
# material, credential files and the names on a list. It reads the tracked files and the ones that are not ignored but not
# staged yet, which the next `git add -A` publishes.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail=0
report() { echo "public-safety: $1" >&2; fail=1; }

files=()
while IFS= read -r f; do files+=("$f"); done < <(git ls-files --cached --others --exclude-standard)
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

# Names that must not appear in tracked files. They are kept here as SHA-256 hashes of the lower-cased name, so this file does
# not carry them either. A word is a run of letters, digits and underscores (what grep's \b sees), and a name of several words
# matches only when its words are separated by single spaces on one line, so `new-file` and a title broken across lines do not.
if ! uv run --quiet --no-project python -I - "${files[@]}" <<'PY'
import hashlib, re, sys

FORBIDDEN = {
    "44f90ec7c496949f67dcab2d6eecbcfccb3191ad65731279529e499a492e7cad",
    "e172f500c51797a312f01190cb042c08036fe57b92cac0aef3ae7b4adcd45212",
    "3b6253a6ddcaf8804e8756d45d342d7ee6ffd580b1bd0042f4b2bd402de060ed",
    "b11afc26e7a3c98f1497d7f54c9afbf00e58e237f3220ab18340f2c4e25af9cf",
    "a2ea5cee4e5bb34ec7948c3b5dbd2e3ddf376ee62ad3e237cce65838d5dfee22",
    "78a81ac6ddd1f11968d625054ae2b71113ec2b5a9648a49897c664c0d2d0caab",
    "7e49d1f53e6084e01a1ae79a621fed42ec2229e5cbe26a6fd9003ddd8541162b",
    "830506288529d5041cbf78a2bc66b0f606f5558a96cf006fde1fdf2f540ffce8",
    "ac919c58701422a07ab1ad81e3b4452dd62d174aea7d56ee306e4fb231442de8",
    "1a2ba7e28d23fb496f09869afb31863cdb555feecede84c7d90d60de49b93b6b",
    "1c24b6d1e3c6809b469466f4220083f7db0ab26bfa0f6436beef88560d8184de",
    "22255ae9689430e666e964b35a579bc0abf4cba6aa996babbd96e7da6d3155f7",
}
LONGEST = 3  # the most words in one of the names

def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()

found = False
for path in sys.argv[1:]:
    if path == "script/verify_public_safety.sh":
        continue
    try:
        with open(path, encoding="utf-8", errors="replace") as file:
            lines = file.read().lower().splitlines()
    except OSError:
        continue
    for number, line in enumerate(lines, 1):
        words = list(re.finditer(r"\w+", line, re.ASCII))
        for start in range(len(words)):
            for end in range(start, min(start + LONGEST, len(words))):
                if end > start and line[words[end - 1].end():words[end].start()] != " ":
                    break
                if digest(line[words[start].start():words[end].end()]) in FORBIDDEN:
                    print(f"{path}:{number}: {line[words[start].start():words[end].end()]}")
                    found = True
sys.exit(1 if found else 0)
PY
then
  report "forbidden name found"
fi

if [[ "$fail" == 1 ]]; then exit 1; fi
echo "public-safety: ok (${#files[@]} files)"
