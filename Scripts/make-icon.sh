#!/bin/sh
# Regenerates Packaging/AppIcon.icns from Assets/AppIcon.svg.
# Run it after changing the SVG and commit the result.
set -eu
cd "$(dirname "$0")/.."

set_dir=build/AppIcon.iconset
mkdir -p "$set_dir"
for size in 16 32 128 256 512; do
    double=$((size * 2))
    swift Scripts/render-icon.swift Assets/AppIcon.svg "$set_dir/icon_${size}x${size}.png" "$size"
    swift Scripts/render-icon.swift Assets/AppIcon.svg "$set_dir/icon_${size}x${size}@2x.png" "$double"
done
iconutil -c icns "$set_dir" -o Packaging/AppIcon.icns
echo "wrote Packaging/AppIcon.icns"
