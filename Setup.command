#!/bin/zsh
# Double-click to (re)generate the Xcode project and open it.
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.homebrew/bin:$PATH"
cd "$(dirname "$0")"
if ! command -v xcodegen >/dev/null; then
  echo "Installing XcodeGen…"; brew install xcodegen || { echo "Could not install XcodeGen."; read; exit 1; }
fi
xcodegen generate && open Nilo.xcodeproj
echo ""; echo "Done. You can close this window."
