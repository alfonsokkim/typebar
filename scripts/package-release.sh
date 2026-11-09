#!/bin/zsh
set -euo pipefail
root="${0:A:h:h}"
if (( $# > 1 )); then
    print -u2 'Usage: scripts/package-release.sh [--development]'
    exit 2
fi
mode=${1:-release}
case "$mode" in
    --development)
        TYPEBAR_SIGN_IDENTITY='' "$root/build.sh" --universal
        cd "$root/dist"
        ditto -c -k --sequesterRsrc --keepParent Typebar.app Typebar-development.zip
        shasum -a 256 Typebar-development.zip > SHA256SUMS-development.txt
        lipo -archs Typebar.app/Contents/MacOS/Typebar
        exit 0
        ;;
    release) ;;
    *) print -u2 'Usage: scripts/package-release.sh [--development]'; exit 2 ;;
esac

# Public downloads must never fall back to a locally signed build.
rm -f "$root/dist/Typebar-mac.zip" "$root/dist/SHA256SUMS.txt"
: "${TYPEBAR_SIGN_IDENTITY:?Set TYPEBAR_SIGN_IDENTITY to a Developer ID Application identity.}"
: "${TYPEBAR_NOTARY_PROFILE:?Set TYPEBAR_NOTARY_PROFILE to a notarytool Keychain profile.}"
xcrun notarytool history --keychain-profile "$TYPEBAR_NOTARY_PROFILE" --output-format json >/dev/null
"$root/build.sh" --universal
cd "$root/dist"
app="$root/dist/Typebar.app"
work=$(mktemp -d "$root/dist/.notarize.XXXXXX")
trap 'rm -rf "$work"' EXIT

ditto -c -k --sequesterRsrc --keepParent "$app" "$work/Typebar-submit.zip"
xcrun notarytool submit "$work/Typebar-submit.zip" \
    --keychain-profile "$TYPEBAR_NOTARY_PROFILE" --wait --output-format json > notary-result.json
result=$(plutil -extract status raw -o - notary-result.json)
if [[ "$result" != Accepted ]]; then
    submission=$(plutil -extract id raw -o - notary-result.json)
    xcrun notarytool log "$submission" --keychain-profile "$TYPEBAR_NOTARY_PROFILE" notary-log.json
    print -u2 'Apple did not accept this build. See dist/notary-log.json. No release ZIP was created.'
    exit 1
fi
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --deep --strict "$app"
spctl --assess --type execute --verbose=2 "$app"

# ZIP the stapled app only after Gatekeeper accepts it.
ditto -c -k --sequesterRsrc --keepParent "$app" "$work/Typebar-mac.zip"
(cd "$work" && shasum -a 256 Typebar-mac.zip > SHA256SUMS.txt)
mv "$work/Typebar-mac.zip" "$work/SHA256SUMS.txt" "$root/dist/"
lipo -archs "$app/Contents/MacOS/Typebar"
print 'Signed, notarized and stapled release: dist/Typebar-mac.zip'
