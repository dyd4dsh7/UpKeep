#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}

# Check the Developer ID settings before the build starts, so a missing one
# fails in seconds rather than after packaging.
: "${UPKEEP_SIGNING_IDENTITY:?Set UPKEEP_SIGNING_IDENTITY to a Developer ID Application certificate name.}"
: "${UPKEEP_NOTARY_PROFILE:?Set UPKEEP_NOTARY_PROFILE to an xcrun notarytool keychain profile.}"

"${SCRIPT_DIR}/package-app.sh" release
