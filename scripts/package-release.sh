#!/bin/zsh
set -euo pipefail
root="${0:A:h:h}"
"$root/build.sh" --universal
cd "$root/dist"
ditto -c -k --sequesterRsrc --keepParent Typebar.app Typebar-mac.zip
shasum -a 256 Typebar-mac.zip > SHA256SUMS.txt
lipo -archs Typebar.app/Contents/MacOS/Typebar
