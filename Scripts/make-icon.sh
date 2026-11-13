#!/bin/sh
# Generates build/AppIcon.icns from Assets/AppIcon.svg. The build script runs
# it; the result is a build product and is not kept in the repository.
set -eu
cd "$(dirname "$0")/.."

set_dir=build/AppIcon.iconset
mkdir -p "$set_dir"
for size in 16 32 128 256 512; do
    double=$((size * 2))
    swift Scripts/render-icon.swift Assets/AppIcon.svg "$set_dir/icon_${size}x${size}.png" "$size"
    swift Scripts/render-icon.swift Assets/AppIcon.svg "$set_dir/icon_${size}x${size}@2x.png" "$double"
done
iconutil -c icns "$set_dir" -o build/AppIcon.icns
echo "wrote build/AppIcon.icns"
