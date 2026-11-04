#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
CONFIGURATION=${1:-release}
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
swift build -c "${CONFIGURATION}" --sdk "${SDK_PATH}" --scratch-path "${BUILD_DIR}" "${LINKER_PLATFORM_FLAGS[@]}"
BIN_DIR=$(swift build -c "${CONFIGURATION}" --sdk "${SDK_PATH}" --scratch-path "${BUILD_DIR}" --show-bin-path)

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

echo "Packaged ${ARCHIVE_PATH}"
