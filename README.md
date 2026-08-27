# DeskPet for DeepSeek Harness

A native macOS desktop-pet companion for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness). It lives in a transparent system-wide desktop window, reacts to Harness task states, displays the current task and editable quick phrases, and can be managed from a dedicated Harness settings section.

[简体中文](README.zh-CN.md)

## Highlights

- Dedicated **Desktop Pet** section inside DeepSeek Harness settings.
- Draggable, transparent, always-on-top native AppKit pet window.
- Double-click focuses an existing Harness tab without navigation or reload.
- Click triggers a random standard animation and an editable quick phrase.
- Running and waiting tasks appear in a bubble above the pet.
- Saved scale, position, visibility, selected pet, and phrases.
- English and Chinese UI follows the current Harness language.
- Supports Codex v1 (1536×1872) and v2 (1536×2288) sprite atlases.
- Catalogs: Awesome Codex Pet, Codex Pets, PetDex, SpriteYard, AgentBro, OpenPets, and Codex Anime Pets.
- Infinite-scroll catalog, retryable downloads, safe image validation, and blank fallback for broken previews.

## Bundled pets

BongoCat is the default. The package also ships with Anya, Shen Xinghui, and the pets present in the maintainer's local **My Pets** collection when this package was assembled. On first launch, missing bundled pets are seeded without overwriting user-installed versions.

Pet artwork is not covered by this repository's MIT code license. See [THIRD_PARTY_PETS.md](THIRD_PARTY_PETS.md). Keep forks containing third-party character art private until redistribution rights have been confirmed.

## Requirements

- macOS 13 or later
- Node.js and pnpm
- A working DeepSeek Harness source checkout that can run `pnpm dsh web`

## Install

```bash
git clone https://github.com/yihanz0107/deskpet-for-deepseek-harness.git
cd deskpet-for-deepseek-harness
./install.sh
```

The installer searches environment variables, saved configuration, common folders, and Spotlight for the Harness checkout. To specify it explicitly:

```bash
./install.sh --harness /path/to/deepseek-harness
```

It builds `~/Applications/DeepSS Pet.app`, installs the Harness Web integration, rebuilds the Web frontend, saves the checkout location, and installs the `deepsshpet` command.

## Run

```bash
deepsshpet
```

This command starts both DeepSeek Harness and the desktop pet. If Harness is already running, it focuses the existing page instead of starting a duplicate service or opening another tab.

You may override discovery for one run:

```bash
DEEPSEEK_HARNESS_HOME=/path/to/deepseek-harness deepsshpet
```

Open **DeepSeek Harness → Settings → Desktop Pet** to select pets, change size, edit quick phrases, show or hide the pet, and open the full-screen catalog.

## Project layout

```text
app/                 Native AppKit pet and bundled pets
bin/deepsshpet       Combined Harness + pet launcher
web/deepss-pet.js    Harness settings and catalog integration
build.sh             Native application build
install.sh           Harness discovery and installation
```

Downloaded pets are stored in `~/Library/Application Support/DeepSS Pet/pets/`. The detected Harness path is stored in `~/.config/deepsshpet/harness-path`.

## Development checks

```bash
node --check web/deepss-pet.js
swiftc -typecheck app/Sources/main.swift \
  -framework AppKit -framework CoreGraphics \
  -framework ImageIO -framework Network
./build.sh
```

## License

Project code is MIT licensed. Third-party pet artwork, characters, and trademarks remain subject to their respective owners and source terms; see [THIRD_PARTY_PETS.md](THIRD_PARTY_PETS.md).
