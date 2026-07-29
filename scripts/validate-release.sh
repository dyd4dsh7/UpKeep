#!/bin/zsh
set -euo pipefail

APP_PATH=${1:-}

if [[ -z "${APP_PATH}" || ! -d "${APP_PATH}" ]]; then
    echo "usage: $0 /path/to/Upkeep.app" >&2
    exit 2
fi

SIGNING_DETAILS=$(codesign -dvvv "${APP_PATH}" 2>&1)
if [[ "${SIGNING_DETAILS}" == *"Signature=adhoc"* ]]; then
    echo "Release validation failed: ${APP_PATH} is ad-hoc signed." >&2
    exit 1
fi
if [[ "${SIGNING_DETAILS}" != *"flags="*"runtime"* ]]; then
    echo "Release validation failed: Hardened Runtime is not enabled." >&2
    exit 1
fi

codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
xcrun stapler validate "${APP_PATH}"
spctl --assess --type execute --verbose=2 "${APP_PATH}"

echo "Release validation passed for ${APP_PATH}"
