#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
host_os=${DEEPSSHPET_OS:-$(uname -s)}

if [ "$host_os" = Linux ]; then
  install_root=${DESKPET_APP_DIR:-"$HOME/.local/share/deepsshpet/app"}
  mkdir -p "$install_root" "$install_root/BundledPets"
  cp "$project_root/cross-platform/package.json" "$project_root/cross-platform/main.cjs" \
    "$project_root/cross-platform/pet.html" "$project_root/cross-platform/pet.css" \
    "$project_root/cross-platform/renderer.js" "$install_root/"
  cp "$project_root/app/Assets/bongocat-spritesheet.png" "$install_root/bongocat-spritesheet.png"
  cp -R "$project_root/app/BundledPets/." "$install_root/BundledPets/"
  (cd "$install_root" && ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/ \
    npm install --omit=dev --no-audit --no-fund --registry=https://registry.npmmirror.com)
  printf 'DeskPet installed for Linux: %s\n' "$install_root"
  exit 0
fi

if [ "$host_os" != Darwin ]; then
  printf 'Unsupported system for build.sh: %s (Windows uses install.ps1)\n' "$host_os" >&2
  exit 1
fi

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
