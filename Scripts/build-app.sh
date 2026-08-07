#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
APP_PATH="$PROJECT_ROOT/dist/TourBox Micro.app"
CONTENTS_PATH="$APP_PATH/Contents"
INSTALL_PATH="/Applications/TourBox Micro.app"
SIGNING_IDENTITY="${TOURBOX_SIGNING_IDENTITY:-}"

if [[ -z "$SIGNING_IDENTITY" && -d "$INSTALL_PATH" ]]; then
    SIGNING_IDENTITY="$(
        /usr/bin/codesign -dv --verbose=4 "$INSTALL_PATH" 2>&1 \
            | /usr/bin/sed -nE 's/^Authority=(Apple Development: .*)$/\1/p' \
            | /usr/bin/head -n 1
    )"
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="$(
        /usr/bin/security find-identity -v -p codesigning \
            | /usr/bin/sed -nE 's/.*"(Apple Development: [^"]+)".*/\1/p' \
            | /usr/bin/head -n 1
    )"
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="-"
    echo "Warning: no Apple Development identity found; using an ad-hoc signature." >&2
    echo "Accessibility permission may need to be granted again after rebuilding." >&2
fi

if [[ "$SIGNING_IDENTITY" != "-" ]] && \
   ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "\"$SIGNING_IDENTITY\""; then
    echo "Signing identity not found: $SIGNING_IDENTITY" >&2
    echo "Set TOURBOX_SIGNING_IDENTITY to '-' or a valid identity from: security find-identity -v -p codesigning" >&2
    exit 1
fi

echo "Signing with: $SIGNING_IDENTITY"

cd "$PROJECT_ROOT"
swift build -c release --product TourBoxMicro

if [[ -d "$APP_PATH" ]]; then
    /bin/rm -rf "$APP_PATH"
fi

/bin/mkdir -p "$CONTENTS_PATH/MacOS" "$CONTENTS_PATH/Resources"
/bin/cp "$PROJECT_ROOT/.build/release/TourBoxMicro" "$CONTENTS_PATH/MacOS/TourBoxMicro"
/bin/cp "$PROJECT_ROOT/Resources/Info.plist" "$CONTENTS_PATH/Info.plist"
/bin/cp "$PROJECT_ROOT/Resources/AppIcon.icns" "$CONTENTS_PATH/Resources/AppIcon.icns"
/bin/cp "$PROJECT_ROOT/LICENSE" "$CONTENTS_PATH/Resources/LICENSE"
/bin/cp "$PROJECT_ROOT/THIRD_PARTY_NOTICES.md" "$CONTENTS_PATH/Resources/THIRD_PARTY_NOTICES.md"
setopt null_glob
for localization_path in "$PROJECT_ROOT"/Resources/*.lproj; do
    /usr/bin/ditto "$localization_path" "$CONTENTS_PATH/Resources/${localization_path:t}"
done
for resource_bundle in "$PROJECT_ROOT"/.build/release/*.bundle; do
    /usr/bin/ditto "$resource_bundle" "$CONTENTS_PATH/Resources/${resource_bundle:t}"
done
/usr/bin/codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp=none \
    --sign "$SIGNING_IDENTITY" \
    "$APP_PATH"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"

if [[ "${1:-}" == "--install" ]]; then
    if [[ "$INSTALL_PATH" != "/Applications/TourBox Micro.app" ]]; then
        echo "Refusing unexpected install path: $INSTALL_PATH" >&2
        exit 1
    fi
    if [[ -e "$INSTALL_PATH" ]]; then
        /bin/rm -rf "$INSTALL_PATH"
    fi
    /usr/bin/ditto "$APP_PATH" "$INSTALL_PATH"
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$INSTALL_PATH"
    /bin/rm -rf "$APP_PATH"
    echo "$INSTALL_PATH"
else
    echo "$APP_PATH"
fi
