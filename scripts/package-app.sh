#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
# release: Developer ID signed and notarized (needs credentials).
# local-release: optimized and stripped, signed locally (ad hoc), not notarized.
# debug: unoptimized development build with symbols.
CONFIGURATION=${1:-release}
case "${CONFIGURATION}" in
    release|local-release) BUILD_CONFIGURATION=release ;;
    debug) BUILD_CONFIGURATION=debug ;;
    *) echo "usage: $0 [release|local-release|debug]" >&2; exit 2 ;;
esac
OUTPUT_DIR=${PROJECT_DIR}/outputs
STAGING_DIR=$(mktemp -d)
BUILD_DIR=$(mktemp -d)
trap 'rm -rf "${STAGING_DIR}" "${BUILD_DIR}"' EXIT
APP_DIR=${STAGING_DIR}/Upkeep.app
ARCHIVE_PATH=${OUTPUT_DIR}/Upkeep.zip

cd "${PROJECT_DIR}"
SDK_NAME=${UPKEEP_SDK:-macosx}
SDK_PATH=$(xcrun --sdk "${SDK_NAME}" --show-sdk-path)
SDK_VERSION=$(xcrun --sdk "${SDK_NAME}" --show-sdk-version)
if (( ${SDK_VERSION%%.*} < 26 )); then
    echo "Upkeep requires the macOS 26 SDK or newer (Xcode 26.6+ recommended)." >&2
    exit 1
fi
LINKER_PLATFORM_FLAGS=(
    -Xlinker -platform_version
    -Xlinker macos
    -Xlinker 14.0
    -Xlinker "${SDK_VERSION}"
)
swift build -c "${BUILD_CONFIGURATION}" --sdk "${SDK_PATH}" --scratch-path "${BUILD_DIR}" "${LINKER_PLATFORM_FLAGS[@]}"
BIN_DIR=$(swift build -c "${BUILD_CONFIGURATION}" --sdk "${SDK_PATH}" --scratch-path "${BUILD_DIR}" --show-bin-path)

mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BIN_DIR}/Upkeep" "${APP_DIR}/Contents/MacOS/Upkeep"
cp "${PROJECT_DIR}/Support/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${PROJECT_DIR}/Support/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
cp "${PROJECT_DIR}/LICENSE" "${APP_DIR}/Contents/Resources/LICENSE"
cp "${PROJECT_DIR}/THIRD_PARTY_NOTICES.md" "${APP_DIR}/Contents/Resources/THIRD_PARTY_NOTICES.md"
ditto "${PROJECT_DIR}/Support/Licenses" "${APP_DIR}/Contents/Resources/Licenses"
if [[ -d "${PROJECT_DIR}/Support/AppIcon.icon" ]]; then
    ditto "${PROJECT_DIR}/Support/AppIcon.icon" "${APP_DIR}/Contents/Resources/AppIcon.icon"
fi
if [[ -d "${BIN_DIR}/Upkeep_Upkeep.bundle" ]]; then
    ditto "${BIN_DIR}/Upkeep_Upkeep.bundle" "${APP_DIR}/Contents/Resources/Upkeep_Upkeep.bundle"
fi
chmod +x "${APP_DIR}/Contents/MacOS/Upkeep"

if [[ "${BUILD_CONFIGURATION}" == "release" ]]; then
    # Keep debug symbols beside the archive for crash symbolication, then
    # strip them from the shipped binary (about 15 MB to 6 MB).
    mkdir -p "${OUTPUT_DIR}"
    rm -rf "${OUTPUT_DIR}/Upkeep.app.dSYM"
    dsymutil "${APP_DIR}/Contents/MacOS/Upkeep" -o "${OUTPUT_DIR}/Upkeep.app.dSYM"
    strip -x "${APP_DIR}/Contents/MacOS/Upkeep"
fi

xattr -cr "${APP_DIR}"
if [[ "${CONFIGURATION}" == "release" ]]; then
    : "${UPKEEP_SIGNING_IDENTITY:?Set UPKEEP_SIGNING_IDENTITY to a Developer ID Application certificate name.}"
    : "${UPKEEP_NOTARY_PROFILE:?Set UPKEEP_NOTARY_PROFILE to an xcrun notarytool keychain profile.}"
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "${UPKEEP_SIGNING_IDENTITY}" \
        "${APP_DIR}"
else
    codesign --force --sign - "${APP_DIR}"
fi
codesign --verify --deep --strict "${APP_DIR}"

mkdir -p "${OUTPUT_DIR}"
STAGED_ARCHIVE=${STAGING_DIR}/Upkeep.zip
ditto -c -k --sequesterRsrc --keepParent "${APP_DIR}" "${STAGED_ARCHIVE}"

if [[ "${CONFIGURATION}" == "release" ]]; then
    xcrun notarytool submit "${STAGED_ARCHIVE}" \
        --keychain-profile "${UPKEEP_NOTARY_PROFILE}" \
        --wait
    xcrun stapler staple "${APP_DIR}"
    xcrun stapler validate "${APP_DIR}"
    rm -f "${STAGED_ARCHIVE}"
    ditto -c -k --sequesterRsrc --keepParent "${APP_DIR}" "${STAGED_ARCHIVE}"
    "${PROJECT_DIR}/scripts/validate-release.sh" "${APP_DIR}"
fi

mv -f "${STAGED_ARCHIVE}" "${ARCHIVE_PATH}"
if [[ "${BUILD_CONFIGURATION}" == "release" ]]; then
    (cd "${OUTPUT_DIR}" && shasum -a 256 Upkeep.zip > Upkeep.zip.sha256)
    # Installed copies of Upkeep only install updates signed with this key.
    UPDATE_KEY=${UPKEEP_UPDATE_SIGNING_KEY:-$HOME/.config/upkeep/update-signing.key}
    rm -f "${OUTPUT_DIR}/Upkeep.zip.sig"
    if [[ -f "${UPDATE_KEY}" ]]; then
        swift "${PROJECT_DIR}/scripts/update-signing.swift" sign "${ARCHIVE_PATH}" "${UPDATE_KEY}" > "${OUTPUT_DIR}/Upkeep.zip.sig"
        echo "Signed ${ARCHIVE_PATH} for in-app updates"
    else
        echo "warning: no update signing key at ${UPDATE_KEY}; Upkeep.zip.sig not created, so in-app updates cannot install this release" >&2
    fi
fi

echo "Packaged ${ARCHIVE_PATH}"
