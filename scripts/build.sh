#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcodegen generate

# Keep personal signing values in the build invocation, outside project files.
typeset -a signing_args
signing_args=()
if [[ -n "${CAPSFLOW_SIGN_IDENTITY:-}" ]]; then
  signing_args+=("CODE_SIGN_IDENTITY=${CAPSFLOW_SIGN_IDENTITY}")
fi
if [[ -n "${CAPSFLOW_DEVELOPMENT_TEAM:-}" ]]; then
  signing_args+=("DEVELOPMENT_TEAM=${CAPSFLOW_DEVELOPMENT_TEAM}")
fi
xcodebuild -project CapsFlow.xcodeproj -scheme CapsFlow -configuration Release \
  -derivedDataPath build "${signing_args[@]}" build
/usr/bin/ditto build/Build/Products/Release/CapsFlow.app CapsFlow.app
