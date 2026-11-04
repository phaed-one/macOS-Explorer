#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account local.pathfind.app
echo "Keep the original Sparkle update-signing key in your Keychain. Never commit or distribute its private key."
