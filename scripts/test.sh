#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./build/Build/Products/Release/CapsFlow.app/Contents/MacOS/CapsFlow --self-test
./build/Build/Products/Release/CapsFlow.app/Contents/MacOS/CapsFlow --smoke-test
codesign --verify --deep --strict CapsFlow.app
