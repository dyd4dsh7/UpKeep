#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
CONFIGURATION=${1:-release}
OUTPUT_DIR=${PROJECT_DIR}/outputs
STAGING_DIR=$(mktemp -d)
BUILD_DIR=$(mktemp -d)
APP_DIR=${STAGING_DIR}/Upkeep.app
ARCHIVE_PATH=${OUTPUT_DIR}/Upkeep.zip

cd "${PROJECT_DIR}"
SDK_VERSION=$(xcrun --sdk macosx --show-sdk-version)
LINKER_PLATFORM_FLAGS=(
    -Xlinker -platform_version
    -Xlinker macos
    -Xlinker 14.0
    -Xlinker "${SDK_VERSION}"
)
swift build -c "${CONFIGURATION}" --scratch-path "${BUILD_DIR}" "${LINKER_PLATFORM_FLAGS[@]}"
BIN_DIR=$(swift build -c "${CONFIGURATION}" --scratch-path "${BUILD_DIR}" --show-bin-path)

mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BIN_DIR}/Upkeep" "${APP_DIR}/Contents/MacOS/Upkeep"
cp "${PROJECT_DIR}/Support/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${PROJECT_DIR}/Support/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
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
if [[ -e "${ARCHIVE_PATH}" ]]; then
    mv "${ARCHIVE_PATH}" "${STAGING_DIR}/previous-Upkeep.zip"
fi
ditto -c -k --sequesterRsrc --keepParent "${APP_DIR}" "${ARCHIVE_PATH}"

if [[ "${CONFIGURATION}" == "release" ]]; then
    xcrun notarytool submit "${ARCHIVE_PATH}" \
        --keychain-profile "${UPKEEP_NOTARY_PROFILE}" \
        --wait
    xcrun stapler staple "${APP_DIR}"
    xcrun stapler validate "${APP_DIR}"
    rm -f "${ARCHIVE_PATH}"
    ditto -c -k --sequesterRsrc --keepParent "${APP_DIR}" "${ARCHIVE_PATH}"
    "${PROJECT_DIR}/scripts/validate-release.sh" "${APP_DIR}"
fi

echo "Packaged ${ARCHIVE_PATH}"
