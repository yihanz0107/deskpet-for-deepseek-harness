#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
requested_harness=''
build_web=true

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
  printf 'DeepSeek Harness was not found. Use: ./install.sh --harness /path/to/deepseek-harness\n' >&2
  exit 1
fi

"$project_root/build.sh"

/usr/bin/ditto "$project_root/web/deepss-pet.js" "$harness_root/apps/web/public/deepss-pet.js"
index_file="$harness_root/apps/web/index.html"
if /usr/bin/grep -q 'deepss-pet.js' "$index_file"; then
  /usr/bin/perl -0pi -e 's#<script src="/deepss-pet\.js(?:\?v=[^"]*)?"></script>#<script src="/deepss-pet.js?v=20260828"></script>#g' "$index_file"
else
  /usr/bin/perl -0pi -e 's#</body>#    <script src="/deepss-pet.js?v=20260828"></script>\n  </body>#' "$index_file"
fi

config_dir="$HOME/.config/deepsshpet"
mkdir -p "$config_dir"
printf '%s\n' "$harness_root" > "$config_dir/harness-path"

launcher_dir="$HOME/.local/bin"
for candidate_dir in /opt/homebrew/bin /usr/local/bin; do
  if [ -d "$candidate_dir" ] && [ -w "$candidate_dir" ]; then
    launcher_dir="$candidate_dir"
    break
  fi
done
mkdir -p "$launcher_dir"
/usr/bin/ditto "$project_root/bin/deepsshpet" "$launcher_dir/deepsshpet"
/bin/chmod +x "$launcher_dir/deepsshpet"

if [ "$build_web" = true ]; then
  (cd "$harness_root" && pnpm run build:web)
fi

printf 'Installed deepsshpet: %s\n' "$launcher_dir/deepsshpet"
printf 'DeepSeek Harness: %s\n' "$harness_root"
printf 'Run: deepsshpet\n'
