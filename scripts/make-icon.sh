#!/bin/zsh
# Regenerates Resources/AppIcon.icns. Usage: scripts/make-icon.sh [plain|glow]
set -euo pipefail
cd "${0:A:h:h}"
SRC=Resources/AppIcon
SET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$SET"
"$SRC/make-svg.sh" "${1:-plain}" > "$SRC/icon.svg"
for size in 16 32 128 256 512; do
    rsvg-convert -w $size -h $size "$SRC/icon.svg" -o "$SET/icon_${size}x${size}.png"
    rsvg-convert -w $((size * 2)) -h $((size * 2)) "$SRC/icon.svg" -o "$SET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
