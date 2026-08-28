#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
host_os=${DEEPSSHPET_OS:-$(uname -s)}
requested_harness=''
build_web=true
toolchain_root=${DEEPSSHPET_TOOLCHAIN_DIR:-"$HOME/.local/share/deepsshpet/toolchain"}

prepend_local_toolchain() {
  PATH="$toolchain_root/pnpm/bin:$toolchain_root/node-current/bin:$PATH"
  export PATH
}

node_is_supported() {
  command -v node >/dev/null 2>&1 && node -e 'const [major, minor] = process.versions.node.split(".").map(Number); process.exit((major === 22 && minor >= 19) || major >= 24 ? 0 : 1)' >/dev/null 2>&1
}

install_node_from_china_mirror() {
  case "$host_os" in
    Darwin) node_platform=darwin ;;
    Linux) node_platform=linux ;;
    *) printf 'Automatic Node.js installation is not supported on %s.\n' "$host_os" >&2; exit 1 ;;
  esac
  case "$(uname -m)" in
    arm64|aarch64) node_arch=arm64 ;;
    x86_64|amd64) node_arch=x64 ;;
    *) printf 'Automatic Node.js installation does not support this CPU: %s\n' "$(uname -m)" >&2; exit 1 ;;
  esac

  for required_command in curl tar; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
      printf '%s is required to install Node.js automatically.\n' "$required_command" >&2
      exit 1
    fi
  done

  printf 'Node.js is missing or incompatible. Installing Node.js 24 from npmmirror...\n'
  download_root=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/deepsshpet-node.XXXXXX")
  trap '/bin/rm -rf "$download_root"' EXIT HUP INT TERM
  node_index="$download_root/node-index.json"
  /usr/bin/curl --location --fail --silent --show-error --max-time 30 \
    'https://registry.npmmirror.com/-/binary/node/index.json' --output "$node_index"
  node_version=$(/usr/bin/grep -m 1 -o '"version":"v24[^"]*"' "$node_index" \
    | /usr/bin/cut -d '"' -f 4)
  if [ -z "$node_version" ]; then
    printf 'Could not determine the latest Node.js 24 version from npmmirror.\n' >&2
    exit 1
  fi

  archive="$download_root/node.tar.gz"
  package_name="node-$node_version-$node_platform-$node_arch"
  /usr/bin/curl --location --fail --show-error --progress-bar \
    "https://registry.npmmirror.com/-/binary/node/$node_version/$package_name.tar.gz" \
    --output "$archive"
  /usr/bin/tar -xzf "$archive" -C "$download_root"
  node_root="$toolchain_root/$package_name"
  mkdir -p "$toolchain_root"
  mkdir -p "$node_root"
  cp -R "$download_root/$package_name/." "$node_root/"
  /bin/ln -sfn "$node_root" "$toolchain_root/node-current"
  /bin/rm -rf "$download_root"
  trap - EXIT HUP INT TERM
  prepend_local_toolchain
  printf 'Installed Node.js: %s\n' "$(node --version)"
}

install_pnpm_from_china_mirror() {
  pnpm_version=$(node -e 'const value = require(process.argv[1]).packageManager || ""; const match = /^pnpm@(.+)$/.exec(value); process.stdout.write(match ? match[1] : "latest")' "$harness_root/package.json")
  printf 'pnpm is missing. Installing pnpm %s from npmmirror...\n' "$pnpm_version"
  mkdir -p "$toolchain_root/pnpm"
  npm install --global --prefix "$toolchain_root/pnpm" \
    --registry=https://registry.npmmirror.com "pnpm@$pnpm_version"
  prepend_local_toolchain
  printf 'Installed pnpm: %s\n' "$(pnpm --version)"
}

prepend_local_toolchain

case "$host_os" in
  Darwin) printf 'Detected macOS. Installing the native desktop pet.\n' ;;
  Linux) printf 'Detected Linux. Installing the cross-platform desktop pet.\n' ;;
  MINGW*|MSYS*|CYGWIN*) printf 'Windows detected. Please run PowerShell: .\\install.ps1\n' >&2; exit 2 ;;
  *) printf 'Unsupported operating system: %s\n' "$host_os" >&2; exit 1 ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    --harness)
      requested_harness=${2:-}
      shift 2
      ;;
    --no-build-web)
      build_web=false
      shift
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

valid_harness() {
  [ -n "${1:-}" ] && [ -f "$1/package.json" ] && [ -f "$1/apps/web/index.html" ]
}

install_harness() {
  install_root=${requested_harness:-${DEEPSEEK_HARNESS_HOME:-"$HOME/deepseek-harness"}}

  if [ -e "$install_root" ]; then
    printf 'Cannot install DeepSeek Harness: %s already exists but is not a valid checkout.\n' "$install_root" >&2
    exit 1
  fi
  if ! command -v git >/dev/null 2>&1; then
    printf 'Cannot install DeepSeek Harness automatically: git is not installed.\n' >&2
    exit 1
  fi

  printf 'DeepSeek Harness was not found. Installing the latest version from GitHub...\n' >&2
  mkdir -p "$(dirname "$install_root")"
  git clone --depth 1 https://github.com/deepseek-ai/deepseek-harness.git "$install_root"
  if ! valid_harness "$install_root"; then
    printf 'The downloaded DeepSeek Harness checkout is not valid: %s\n' "$install_root" >&2
    exit 1
  fi
  printf '%s\n' "$install_root"
}

find_harness() {
  saved_root=''
  if [ -f "$HOME/.config/deepsshpet/harness-path" ]; then
    saved_root=$(sed -n '1p' "$HOME/.config/deepsshpet/harness-path")
  fi
  for candidate_root in "$requested_harness" "${DEEPSEEK_HARNESS_HOME:-}" "$saved_root" "$HOME/deepseek-harness" "$HOME/Projects/deepseek-harness" "$HOME/Documents/deepseek-harness" "$HOME/Desktop/deepseek-harness"; do
    if valid_harness "$candidate_root"; then
      printf '%s\n' "$candidate_root"
      return 0
    fi
  done
  if command -v mdfind >/dev/null 2>&1; then
    located_root=$(mdfind 'kMDItemFSName == "deepseek-harness"c' | while IFS= read -r found_root; do
      if valid_harness "$found_root"; then
        printf '%s\n' "$found_root"
        break
      fi
    done)
    if valid_harness "$located_root"; then
      printf '%s\n' "$located_root"
      return 0
    fi
  fi
  find "$HOME" -maxdepth 4 -type d -name deepseek-harness 2>/dev/null | while IFS= read -r found_root; do
    if valid_harness "$found_root"; then
      printf '%s\n' "$found_root"
      break
    fi
  done
}

harness_root=$(find_harness || true)
if ! valid_harness "$harness_root"; then
  harness_root=$(install_harness)
fi

if ! node_is_supported; then
  install_node_from_china_mirror
fi
if ! command -v pnpm >/dev/null 2>&1; then
  if ! command -v npm >/dev/null 2>&1; then
    install_node_from_china_mirror
  fi
  install_pnpm_from_china_mirror
fi

if [ ! -d "$harness_root/node_modules" ]; then
  printf 'Installing DeepSeek Harness dependencies...\n'
  (cd "$harness_root" && pnpm install --frozen-lockfile)
fi

"$project_root/build.sh"

cp "$project_root/web/deepss-pet.js" "$harness_root/apps/web/public/deepss-pet.js"
index_file="$harness_root/apps/web/index.html"
INDEX_FILE="$index_file" node - <<'NODE'
const fs = require('node:fs')
const file = process.env.INDEX_FILE
let html = fs.readFileSync(file, 'utf8')
const tag = '<script src="/deepss-pet.js?v=20260828"></script>'
html = /<script src="\/deepss-pet\.js(?:\?v=[^"]*)?"><\/script>/.test(html)
  ? html.replace(/<script src="\/deepss-pet\.js(?:\?v=[^"]*)?"><\/script>/g, tag)
  : html.replace('</body>', `    ${tag}\n  </body>`)
fs.writeFileSync(file, html)
NODE

config_dir="$HOME/.config/deepsshpet"
mkdir -p "$config_dir"
printf '%s\n' "$harness_root" > "$config_dir/harness-path"

launcher_dir="$HOME/.local/bin"
if [ "$host_os" = Darwin ]; then
  for candidate_dir in /opt/homebrew/bin /usr/local/bin; do
    if [ -d "$candidate_dir" ] && [ -w "$candidate_dir" ]; then launcher_dir="$candidate_dir"; break; fi
  done
fi
mkdir -p "$launcher_dir"
cp "$project_root/bin/deepsshpet" "$launcher_dir/deepsshpet"
/bin/chmod +x "$launcher_dir/deepsshpet"

if [ "$build_web" = true ]; then
  # A fresh Harness checkout has no generated workspace artifacts yet. The
  # root build creates those artifacts before it builds the Web frontend.
  (cd "$harness_root" && pnpm run build)
fi

printf 'Installed deepsshpet: %s\n' "$launcher_dir/deepsshpet"
printf 'DeepSeek Harness: %s\n' "$harness_root"
printf 'Run: deepsshpet\n'
if [ "$host_os" = Linux ]; then
  case ":$PATH:" in *":$launcher_dir:"*) ;; *) printf 'Add %s to PATH if the command is not found.\n' "$launcher_dir" ;; esac
fi
