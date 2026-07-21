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
swift build -c "${CONFIGURATION}" --scratch-path "${BUILD_DIR}"
BIN_DIR=$(swift build -c "${CONFIGURATION}" --scratch-path "${BUILD_DIR}" --show-bin-path)

mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BIN_DIR}/Upkeep" "${APP_DIR}/Contents/MacOS/Upkeep"
cp "${PROJECT_DIR}/Support/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${PROJECT_DIR}/Support/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
if [[ -d "${BIN_DIR}/Upkeep_Upkeep.bundle" ]]; then
    ditto "${BIN_DIR}/Upkeep_Upkeep.bundle" "${APP_DIR}/Contents/Resources/Upkeep_Upkeep.bundle"
fi
chmod +x "${APP_DIR}/Contents/MacOS/Upkeep"

xattr -cr "${APP_DIR}"
codesign --force --deep --sign - "${APP_DIR}"
codesign --verify --deep --strict "${APP_DIR}"

mkdir -p "${OUTPUT_DIR}"
if [[ -e "${ARCHIVE_PATH}" ]]; then
    mv "${ARCHIVE_PATH}" "${STAGING_DIR}/previous-Upkeep.zip"
fi
ditto -c -k --sequesterRsrc --keepParent "${APP_DIR}" "${ARCHIVE_PATH}"
echo "Packaged ${ARCHIVE_PATH}"
