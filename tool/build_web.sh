#!/usr/bin/env bash
# Builds the endgame-search web worker (web/search_worker.js, git-ignored)
# that `flutter build web` / `flutter run -d chrome` then serve next to the
# app. Without it the web app searches on the page's thread (slower).
#
#   tool/build_web.sh            # worker only
#   tool/build_web.sh build ...  # worker, then `flutter build web ...`
set -euo pipefail
cd "$(dirname "$0")/.."
dart compile js -O4 lib/services/local/search_worker_main.dart \
  -o web/search_worker.js
rm -f web/search_worker.js.deps web/search_worker.js.map
if [[ "${1:-}" == build ]]; then
  shift
  flutter build web "$@"
fi
