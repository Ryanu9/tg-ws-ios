#!/usr/bin/env bash
# Dev helper: regenerates telegram-ios-ws.patch from a modified Telegram-iOS checkout.
#   scripts/make-patch.sh /path/to/Telegram-iOS
set -euo pipefail
SRC="${1:?usage: make-patch.sh /path/to/Telegram-iOS}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/telegram-ios-ws.patch"
cd "$SRC"
git add -N submodules/WsBridge submodules/TelegramCore/Sources/WsBridge
git diff --binary HEAD -- . ':(exclude)build-input' > "$OUT"
git rev-parse HEAD > "$(dirname "$OUT")/UPSTREAM_COMMIT"
echo "wrote $OUT ($(grep -c '^diff --git' "$OUT") files)"
