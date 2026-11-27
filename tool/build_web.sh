#!/usr/bin/env bash
# Builds what the web app serves next to it (git-ignored, in web/): the
# play-net wasm kernel (web_kernel/build.sh, needs clang) and the
# endgame-search worker (web/search_worker.js). Run it before
# `flutter build web` / `flutter run -d chrome`; without them the web bots
# score in Dart and search on the page's thread (several times slower).
#
#   tool/build_web.sh            # worker only
#   tool/build_web.sh build ...  # worker, then `flutter build web ...`
set -euo pipefail
cd "$(dirname "$0")/.."
web_kernel/build.sh
dart compile js -O4 lib/services/local/search_worker_main.dart \
  -o web/search_worker.js
rm -f web/search_worker.js.deps web/search_worker.js.map
if [[ "${1:-}" == build ]]; then
  shift
  flutter build web "$@"
fi
