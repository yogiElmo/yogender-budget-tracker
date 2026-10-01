#!/usr/bin/env bash
# After `flutter build web`: give each release's files a unique URL so phones
# can't mix cached old files with new ones, and publish the version number
# the app checks on start.
set -euo pipefail
VERSION="$1"
cd build/web
sed -i "s#\"main\.dart\.js\"#\"main.dart.js?v=${VERSION}\"#g" flutter_bootstrap.js
sed -i "s#src=\"flutter_bootstrap\.js\"#src=\"flutter_bootstrap.js?v=${VERSION}\"#" index.html
printf '{"version":"%s"}\n' "$VERSION" > version.json
grep -q "main.dart.js?v=${VERSION}" flutter_bootstrap.js
grep -q "flutter_bootstrap.js?v=${VERSION}" index.html
echo "Stamped version ${VERSION}"
