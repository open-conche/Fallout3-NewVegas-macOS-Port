# Fallout 3 & Fallout: New Vegas for macOS (Apple Silicon)

Native Apple Silicon (`arm64`) macOS ports of **Fallout 3: Game of the Year Edition** and **Fallout: New Vegas**, built with **x86-to-C/ARM64 static recompilation** and direct **Direct3D 9 → Apple Metal** translation. Each game is packaged as its own standalone bundle (`Fallout 3.app`, `Fallout New Vegas.app`) with no Wine, CrossOver, Rosetta 2, or virtual machines required.

Both games are translated by the same recompiler and installed by the same `quick-install.sh`; the script identifies the game from the executable it finds and asks which one to build when several installations are present.

---

## Why This Port Exists (Wine Challenges vs. Recent Improvements)

*Fallout 3* and *Fallout: New Vegas* share the Gamebryo engine and the same three traits that have historically made them a worst-case scenario under Wine on Apple Silicon:

1. **32-bit x86 executable**
2. **Heavy x87 (80-bit) floating-point usage** — which Rosetta 2 emulates slowly in software, requiring external hooks like `rosettax87_jit` or `x87sidecar` (rarely bundled in standard Wine wrappers).
3. **Direct3D 9** — which is unsupported by **D3DMetal (GPTK)** and **DXMT** (both focused on Direct3D 10/11/12), while the older macOS DXVK fork had limitations on top of MoltenVK.

While the Wine ecosystem has improved recently — with **Wine ARM64 + FEX** in reduced-precision mode (such as CodeWeavers' CrossOver Preview) and new D3D9-to-Metal renderers (such as `mtld3d` / `Mach9`) — many free wrappers (like Sikarugir) still rely on traditional Intel Wine + Rosetta 2.

These ports eliminate that entire stack at the root:
* **No Rosetta 2 or FEX overhead:** game code is statically recompiled to **native ARM64**, with x87 arithmetic lowered to 64-bit `double` (53-bit precision, matching what the MSVC CRT configures on Windows).
* **Lower RAM footprint:** running as a single native process without `wineserver` or x86 translation layers saves significant memory — especially valuable on **8 GB unified-memory** Apple Silicon Macs.
* **Direct D3D9 → Metal:** D3D9 calls and SM 1–3 shaders compile directly to Metal (`d3d9_metal.m` and `sm2msl.c`).

---

## What Changed Compared to Upstream

This repository adapts **[FNV-iOS-Shim](https://github.com/arjuk95-dot/FNV-iOS-Shim)** (which itself builds on **[Fallout-NV-MacOS](https://github.com/thetheoryofR/Fallout-NV-MacOS)**) back into desktop **macOS** ports, and extends the recompiler from *Fallout: New Vegas* to *Fallout 3*:

* **Build target switched from iOS (UIKit) to macOS (AppKit):**
  * Removed the `ios/` layer (touch controls, overlay editor, gyro handling, `verify_ipa.py`, and touch UI tests).
  * Added the `macos/` layer with an AppKit window (`FNVApp.m`), **macOS Game Mode** support (`LSApplicationCategoryType: public.app-category.games`), automatic relative mouse capture while focused (released on `Cmd+Tab`), DirectInput keyboard mapping (`dinput.c` / `input.c`), and `GameController.framework` support (`FNVPad.c`).
  * Retained `FNV-iOS-Shim` media and stability improvements: native PCM mixer (`FNVAudioMixer.c` + `AVAudioEngine`), Ogg/Vorbis decoding, DirectShow pull-source (`dshow.m`), native `AVFoundation` cutscene playback (`FNVNativeVideo.m`), and heap/texture/sync fixes.
* **Restored Unicorn Engine fallback:**
  * `FNV-iOS-Shim` had removed Unicorn fallback execution due to iOS restrictions. This port restores `upstream/recomp/host/fallback.c` and links `libunicorn.a` to handle any uncompiled code paths or edge-case instructions.
* **Precomputed symbol maps for four executables (`symbols/fallout3/`, `symbols/fallout3-steam/`, `symbols/fnv/`, `symbols/fnv-steam/`):**
  * The original iOS project shipped without symbol maps and required a full Ghidra auto-analysis (~40 minutes) even though it only targeted a single executable.
  * Precomputed function and jump-table metadata for the **GOG and Steam** builds of both games plus `tools/ghidra/ApplyMetadataAndDump.java` cut the Ghidra step down to **~1 min** P-code export + **~3 min** C emission. `tools/ghidra/ExportSymbols.java` exports a new map from an analysed executable, so another build can be added without redoing the analysis on every install. For DRM-free executables outside the precomputed set, the full Ghidra pipeline (`FixNoReturn.java`, `ResolveJumpTables.java`, `FixEntries.java`, `DumpPcode.java`) remains available automatically as a fallback.
* **One-command installer & packager (`quick-install.sh`):**
  * Auto-detects **both games** across common locations (Steam, SteamCMD, DepotDownloader, GOG `innoextract`, `~/Downloads`, `~/Games`, or an existing `.app`), scans every candidate instead of stopping at the first hit, and presents a numbered menu when more than one installation is present — for example *Fallout 3: Game of the Year Edition (GOG)* and *Fallout: New Vegas (Steam)*. `--game fnv|fallout3` restricts the search to one game.
  * Checks for SteamStub `.bind` DRM (offering to back up the executable to `.exe.og` and strip the DRM using official Steamless CLI + Mono on demand), verifies the executable SHA-256, installs missing Homebrew dependencies (`ghidra`, `unicorn`, `cmake`, `ffmpeg`, plus `mono` if needed), caches codecs/objects/translations under `~/Library/Caches/fnv-macos/`, moves game data into `<App>.app/Contents/Resources/GameData/`, converts `.bik` cutscenes to `.mp4` via `ffmpeg`, ad-hoc signs the bundle, and optionally wraps it in a `.dmg` (`--dmg`).
* **Additional codebase changes:**
  * **Optional Steamworks bridge & Overlay launcher (Steam builds only):** `upstream/recomp/host/shims_steam.c` loads Valve's official ARM64 `libsteam_api.dylib` (bundled only for Steam builds, omitted for GOG or `--no-steam`) to bridge `steam_api.dll` (`__thiscall` proxies for `ISteamUser`, `ISteamUtils`, `ISteamUserStats`, `ISteamApps`, and `ISteamFriends`, plus `SteamAPI_ManualDispatch_*` callbacks) for Steam achievements and status, with clean offline fallback. `macos/FNVSteamLauncher.c` starts the Mac Steam client silently (`-silent`), waits for global user login (`ConnectToGlobalUser`) before launching the game, and injects `gameoverlayrenderer.dylib` for the Metal Steam Overlay (`Shift+Tab`) and, where the game exposes Steamworks (Fallout: New Vegas), achievement notifications. The launcher takes the target executable and AppID from the build (`FalloutNewVegas`/22380 for FNV, `Fallout3`/22370 for Fallout 3).
  * **Fallout 3 specifics:** per-game title, save/log directories, and a `plugins.txt` bootstrap seeded from `Data/DLCList.txt` so all five GOTY add-ons load; xlive (Games for Windows - LIVE) stubs for the GOG build and winsock offline stubs for both; per-game `.icns` icons (`macos/Assets/AppIcon.png` for FNV, `macos/Assets/AppIcon-Fallout3.png` for Fallout 3).
  * **User data outside the bundle (`FNV_USER_DIR`):** updates in `upstream/recomp/host/shims_files.c` and `shims_win.c` (`SHGetFolderPathA`) route `UserDocuments` (saves, `FALLOUT.INI`, `FalloutPrefs.ini`) to `~/Library/Application Support/FalloutNV/UserDocuments` or `~/Library/Application Support/Fallout3/UserDocuments`, with logs in `~/Library/Logs/FalloutNV/fnv.log` or `~/Library/Logs/Fallout3/fallout3.log`.
  * **macOS 14+ Metal compatibility (`d3d9_metal.m`):** guarded `copts.mathMode = MTLMathModeSafe` with `@available(macOS 15.0, iOS 18.0, *)` so the port builds and runs cleanly on macOS 14 (Sonoma) and newer.
  * **Build & test suite updates (`tools/build.py`, `tools/app_icon.py`, `tests/`):** updated build scripts and native/host test suite for the macOS target; `tools/build.py --game fallout3` selects the Fallout 3 profile (bundle identifier `dev.f3mac.fallout3`, executable name, define, icon).

---

## Requirements & Supported Builds

* **Apple Silicon Mac (`arm64`)** running **macOS 14 (Sonoma)** or later.
* **Xcode Command Line Tools** (`xcode-select --install`) and **Homebrew**.
* **Your own PC copy** of at least one of the two games:

### Fallout 3: Game of the Year Edition

| Store | Executable | Version | SHA-256 | Symbols |
|---|---|---|---|---|
| **GOG** | `Fallout3.exe` | 1.7.0.3 | `df9f0e1ec2c5413a9cef2db2dde6d926b99707d528049af4eb15538587d55f99` | `symbols/fallout3/` |
| **Steam** | `Fallout3.exe` | 1.7.0.4 | `c3f97c2255fa041a851c17cf372d69aaadd8694e2dc4230ba556001bbfbd2f3e` | `symbols/fallout3-steam/` |

* The precomputed symbols cover the **GOG 1.7.0.3** installer (`setup_fallout_3_1.7.0.3_(12034).exe`) and the current **Steam 1.7.0.4** build (the 2021 patch that removed Games for Windows - LIVE). The GOTY edition bundles all five add-ons (Operation: Anchorage, The Pitt, Broken Steel, Point Lookout, Mothership Zeta).
* Steam's **22370** is the Game of the Year Edition. **22300** is the original 2008 release, which is still listed on Steam; its executable may not match the precomputed SHA-256, in which case `quick-install.sh` falls back to full Ghidra auto-analysis.
* Our Steam GOTY copy ships without a SteamStub `.bind` section. If yours is still packed, the installer detects the DRM and can strip it with Steamless exactly as for FNV.
* **No Steam achievements:** the 2021 Steam patch removed GFWL and no Steamworks achievements were added (the store page lists only Single-player/Family Sharing). The Steam Overlay and status integration still work.

### Fallout: New Vegas

| Store | Executable | SHA-256 | Symbols |
|---|---|---|---|
| **GOG** | `FalloutNV.exe` | `89e7020487e80f20ddc92ea641c4433b2c6839a82f45a076e414d167d11dd0fe` | `symbols/fnv/` |
| **Steam** (after Steamless) | `FalloutNV.exe` | `19406942e48724d797300c4ea6be9ac69a32f670b8c35db09279a2258422739f` | `symbols/fnv-steam/` |
| **Steam** (original, SteamStub v2.1) | `FalloutNV.exe` | `3a87f92f011e5dc9179ddf733cf08be2b39ea6e5b7a8a9e3a9a72dafcc1b104d` | strip first |

* GOG builds launch `FalloutNewVegas` directly and completely standalone — no Steam launch, no Steam Overlay, and no `libsteam_api.dylib`.
* For Steam builds, when `quick-install.sh` detects SteamStub DRM it warns you and asks for confirmation (or pass `--unpack-drm`) to automatically install `mono` (via Homebrew if missing), download the official [Steamless](https://github.com/atom0s/Steamless) CLI release (`v3.1.0.5`, verified by SHA-256), back up the original file to `FalloutNV.exe.og`, strip the DRM, and compile using `symbols/fnv-steam/`.
* **Steam Achievements & Overlay:** `quick-install.sh` fetches Valve's official ARM64 `libsteam_api.dylib` (from Steamworks.NET 20.1.0, verified by SHA-256) into `Contents/Frameworks/` and bundles `FalloutNewVegasLauncher` so double-clicking `Fallout New Vegas.app` automatically starts the Mac Steam client (if installed) and enables achievements, Steam status, and the Steam Overlay (`Shift+Tab`). Pass `--no-steam` at build time to omit Steam integration, or set `FNV_STEAM_NO_OVERLAY=1` / `FNV_STEAM_DISABLE=1` at runtime.
* **Epic Games Store / other DRM-free builds:** if the SHA-256 differs from the GOG and Steam builds above, `quick-install.sh` automatically falls back to full Ghidra auto-analysis (slower, and unsupported builds may require address adjustments if the binary layout differs).

---

## Obtaining the Windows Game Files on macOS

Because both games are Windows-only on Steam and GOG, you can fetch or extract the game files directly on your Mac using any of the methods below. All output paths shown here are auto-detected by `quick-install.sh`.

### Option 1: Steam

> **AppID note:** Fallout 3 is **22370** (Game of the Year Edition, includes all DLC) or **22300** (original 2008 release). Fallout: New Vegas is **22380** (standard global edition); use **22490** instead if your Steam account owns the regional PCR edition.

#### Method A — `steamcmd` (recommended)

```sh
brew install --cask steamcmd
# Fallout 3: Game of the Year Edition
steamcmd +@sSteamCmdForcePlatformType windows +login <YOUR_STEAM_USERNAME> +app_update 22370 validate +quit
# Fallout: New Vegas
steamcmd +@sSteamCmdForcePlatformType windows +login <YOUR_STEAM_USERNAME> +app_update 22380 validate +quit
```

*This downloads the game (along with any DLCs owned by your account) directly into `~/Library/Application Support/Steam/steamapps/common/Fallout 3 goty` (22300 installs as `.../common/Fallout 3`) / `.../Fallout New Vegas` (or the equivalent under `~/Steam/steamapps/common/`), both of which `quick-install.sh` auto-detects. Pass `+force_install_dir "$HOME/Downloads/Fallout 3"` (or `.../Fallout New Vegas`) before `+login` if you prefer a separate folder.*

#### Method B — `DepotDownloader`

```sh
brew tap steamre/tools
brew install depotdownloader
# Fallout 3: Game of the Year Edition
depotdownloader -app 22370 -os windows -username <YOUR_STEAM_USERNAME> \
  -dir "$HOME/Downloads/Fallout 3"
# Fallout: New Vegas
depotdownloader -app 22380 -os windows -username <YOUR_STEAM_USERNAME> \
  -dir "$HOME/Downloads/Fallout New Vegas"
```

*If you omit `-dir`, DepotDownloader places files under `./depots/<appid>/<manifest>/` (`~/depots/22370/`, `~/Downloads/depots/22370/`, the same paths for `22300`, `22380`, `22490` are all auto-detected).*

#### Method C — Steam Client Console

1. Open the hidden Console tab in the desktop Steam client:
   ```sh
   open "steam://open/console"
   ```
2. Download the game depots (plus any DLC depots you own — check the app's depot IDs on SteamDB if needed):
   ```text
   download_depot 22370 <DEPOT_ID>
   download_depot 22380 <DEPOT_ID>
   ```
3. Steam saves each depot separately under:
   `~/Library/Application Support/Steam/steamapps/content/app_<APPID>/depot_*/`
   Merge the contents of those `depot_*` folders into one folder (for example `~/Downloads/Fallout 3/`) so `Fallout3.exe`/`FalloutNV.exe` and `Data/` sit together.

### Option 2: GOG Offline Installer (`innoextract`)

If you downloaded the GOG offline backup installer to `~/Downloads/`:

```sh
brew install innoextract
# Fallout 3: Game of the Year Edition (setup_fallout_3_1.7.0.3_(12034).exe plus -1.bin/-2.bin)
innoextract -d "$HOME/Downloads/Fallout 3" ~/Downloads/setup_fallout_3_*.exe
# Fallout: New Vegas (setup_fallout_new_vegas_*.exe and its .bin parts)
innoextract -d "$HOME/Downloads/Fallout New Vegas" ~/Downloads/setup_fallout_new_vegas_*.exe
```

*Both installers extract the playable files under `app/`: for Fallout 3 that is `~/Downloads/Fallout 3/app/Fallout3.exe` plus `app/Data/` (`Fallout3.esm`, the five DLC `.esm`/`.bsa` pairs and `Data/Video/*.bik`), with GOG metadata in `app/goggame-*.info`. Running `innoextract` without `-d` inside `~/Downloads` produces `~/Downloads/app/`, which is also detected. The detector accepts the extraction folder, its `app/` child, or an explicit path, so `quick-install.sh` finds it automatically.*

---

## Quick Install

```sh
# Auto-detect either game. If both games (or several copies) are installed, a menu asks
# which one to build.
./quick-install.sh

# Restrict detection to one game
./quick-install.sh --game fallout3
./quick-install.sh --game fnv

# Or pass an explicit path (game folder, innoextract output, or a parent containing both)
./quick-install.sh "/path/to/Fallout 3"
./quick-install.sh "/path/to/Fallout New Vegas"
```

When more than one installation is found, the selector looks like this:

```text
Multiple game installations found:
  1) Fallout: New Vegas (Steam) — /Users/you/Library/Application Support/Steam/steamapps/common/Fallout New Vegas
  2) Fallout 3: Game of the Year Edition (GOG) — /Users/you/Downloads/Fallout 3/app
  Select the game to build [1-2]:
```

In a non-interactive shell the script stops with the same list and asks you to pass a folder or `--game`.

To skip the confirmation prompt when stripping SteamStub DRM, or to wrap the app in a drag-to-Applications `.dmg`:

```sh
./quick-install.sh --unpack-drm --dmg
```

> **Note on disk usage:** to avoid duplicating roughly 9–10 GB per game, `quick-install.sh` **moves** the game files from the source folder into `~/Applications/Fallout 3.app` or `~/Applications/Fallout New Vegas.app` (`Contents/Resources/GameData/`). Because of that move, the original Steam/GOG installation is no longer playable on its own; use Steam's *Verify integrity of game files* (or reinstall/extract again) if you want it back. Translation and object caches are stored in `~/Library/Caches/fnv-macos/`.

---

## Manual Build & Tests

```sh
# Compile host-only check (no game files required)
python3 tools/build.py host-check

# Build standalone Metal/input probe app
python3 tools/build.py probe --out build/probe-test

# Run native host/media test suite
bash tests/run.sh
```

---

## Credits

* **[Fallout-NV-MacOS](https://github.com/thetheoryofR/Fallout-NV-MacOS)** (by **thetheoryofR**) — Original x86→C/ARM64 static recompiler, D3D9→Metal renderer, Win32/COM host, and Unicorn fallback (MIT license in `upstream/LICENSE`).
* **[FNV-iOS-Shim](https://github.com/arjuk95-dot/FNV-iOS-Shim)** (by **arjuk95-dot**) — Native audio mixer (`AVAudioEngine`), Ogg/Vorbis bridge, `AVFoundation` video, DirectShow pull-source, and heap/texture/sync fixes.
* **[macIV](https://github.com/tanmayisdumb/macIV)** — App bundle packaging and `quick-install.sh` UX inspiration.
