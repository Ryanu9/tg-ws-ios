#!/usr/bin/env bash
# Builds the patched source tree on a Mac (macOS 27 + Xcode 27.1):
#   scripts/apply-patch.sh ~/telegram-ios
# then build with the command printed at the end.
set -euo pipefail
DEST="${1:?usage: apply-patch.sh /path/to/new/telegram-ios}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
git init -q "$DEST"
cd "$DEST"
git remote add origin https://github.com/TelegramMessenger/Telegram-iOS.git
git fetch -q --depth 1 origin "$(cat "$HERE/UPSTREAM_COMMIT")"
git checkout -q FETCH_HEAD
git submodule update --init --recursive --depth 1 --jobs 8
git apply --whitespace=nowarn "$HERE/telegram-ios-ws.patch"
cat <<MSG
Patched tree ready in $DEST. Build an IPA with:

  cd "$DEST"
  python3 build-system/Make/ImportCertificates.py --path build-system/fake-codesigning/certs
  python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir="\$HOME/telegram-bazel-cache" build \\
    --configurationPath=build-system/appstore-configuration.json \\
    --codesigningInformationPath=build-system/fake-codesigning \\
    --configuration=release_arm64 --buildNumber=1 --outputBuildArtifactsPath=build/artifacts
MSG
