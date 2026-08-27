#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
app_source="$project_root/app"
build_root="$project_root/build"
app_bundle="$build_root/DeepSS Pet.app"
install_root=${DESKPET_APP_DIR:-"$HOME/Applications/DeepSS Pet.app"}

mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources" "$(dirname "$install_root")"
/usr/bin/swiftc -O \
  -framework AppKit \
  -framework CoreGraphics \
  -framework ImageIO \
  -framework Network \
  "$app_source/Sources/main.swift" \
  -o "$app_bundle/Contents/MacOS/DeepSSPet"

/usr/bin/ditto "$app_source/Info.plist" "$app_bundle/Contents/Info.plist"
/usr/bin/ditto "$app_source/Assets/bongocat-spritesheet.png" "$app_bundle/Contents/Resources/spritesheet.png"
/usr/bin/ditto "$app_source/BundledPets" "$app_bundle/Contents/Resources/BundledPets"
/usr/bin/codesign --force --deep --sign - "$app_bundle"
/usr/bin/ditto "$app_bundle" "$install_root"
printf 'DeskPet installed: %s\n' "$install_root"
