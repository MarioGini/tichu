#!/usr/bin/env bash
# Clones the external bots at the commits the adapters were written against
# into arena/.bots/ (not committed: other people's code, own licenses).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .bots
while read -r repo sha; do
  [[ -z "$repo" || "$repo" == \#* ]] && continue
  dir=".bots/${repo/\//__}"
  if [[ ! -d "$dir" ]]; then
    git clone -q "https://github.com/$repo" "$dir"
  fi
  git -C "$dir" fetch -q --depth 1 origin "$sha" 2>/dev/null || true
  git -C "$dir" checkout -q "$sha"
  echo "$repo @ ${sha:0:9}"
done < bots.txt
