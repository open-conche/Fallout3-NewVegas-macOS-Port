# Fallout: New Vegas for macOS (Apple Silicon)

A native Apple Silicon (`arm64`) macOS port of **Fallout: New Vegas** using **x86-to-C/ARM64 static recompilation** and direct **Direct3D 9 → Apple Metal** translation, packaged as a standalone `Fallout New Vegas.app` bundle with no Wine, CrossOver, Rosetta 2, or virtual machines required.

---

## Why This Port Exists (Wine Challenges vs. Recent Improvements)

*Fallout: New Vegas* combines three traits that have historically made it a worst-case scenario under Wine on Apple Silicon:

1. **32-bit x86 executable**
2. **Heavy x87 (80-bit) floating-point usage** — which Rosetta 2 emulates slowly in software, requiring external hooks like `rosettax87_jit` or `x87sidecar` (rarely bundled in standard Wine wrappers).
3. **Direct3D 9** — which is unsupported by **D3DMetal (GPTK)** and **DXMT** (both focused on Direct3D 10/11/12), while the older macOS DXVK fork had limitations on top of MoltenVK.

While the Wine ecosystem has improved recently — with **Wine ARM64 + FEX** in reduced-precision mode (such as CodeWeavers' CrossOver Preview) and new D3D9-to-Metal renderers (such as `mtld3d` / `Mach9`) — many free wrappers (like Sikarugir) still rely on traditional Intel Wine + Rosetta 2.

This port eliminates that entire stack at the root:
* **No Rosetta 2 or FEX overhead:** game code is statically recompiled to **native ARM64**, with x87 arithmetic lowered to 64-bit `double` (53-bit precision, matching what the MSVC CRT configures on Windows).
* **Lower RAM footprint:** running as a single native process without `wineserver` or x86 translation layers saves significant memory — especially valuable on **8 GB unified-memory** Apple Silicon Macs.
* **Direct D3D9 → Metal:** D3D9 calls and SM 1–3 shaders compile directly to Metal (`d3d9_metal.m` and `sm2msl.c`).

---

## What Changed Compared to Upstream

This repository adapts **[FNV-iOS-Shim](https://github.com/arjuk95-dot/FNV-iOS-Shim)** (which itself builds on **[Fallout-NV-MacOS](https://github.com/thetheoryofR/Fallout-NV-MacOS)**) back into a desktop **macOS** port:

* **Build target switched from iOS (UIKit) to macOS (AppKit):**
  * Removed the `ios/` layer (touch controls, overlay editor, gyro handling, `verify_ipa.py`, and touch UI tests).
  * Added the `macos/` layer with an AppKit window (`FNVApp.m`), **macOS Game Mode** support (`LSApplicationCategoryType: public.app-category.games`), automatic relative mouse capture while focused (released on `Cmd+Tab`), DirectInput keyboard mapping (`dinput.c` / `input.c`), and `GameController.framework` support (`FNVPad.c`).
  * Retained `FNV-iOS-Shim` media and stability improvements: native PCM mixer (`FNVAudioMixer.c` + `AVAudioEngine`), Ogg/Vorbis decoding, DirectShow pull-source (`dshow.m`), native `AVFoundation` cutscene playback (`FNVNativeVideo.m`), and heap/texture/sync fixes.
* **Restored Unicorn Engine fallback:**
  * `FNV-iOS-Shim` had removed Unicorn fallback execution due to iOS restrictions. This port restores `upstream/recomp/host/fallback.c` and links `libunicorn.a` to handle any uncompiled code paths or edge-case instructions.
* **Precomputed symbol maps (`symbols/fnv/` and `symbols/fnv-steam/`):**
  * The original iOS project shipped without symbol maps and required a full Ghidra auto-analysis (~40 minutes) even though it only targeted a single executable.
  * Precomputed function and jump-table metadata for both the **GOG** (`symbols/fnv/`) and **Steam** (`symbols/fnv-steam/`) builds plus `tools/ghidra/ApplyMetadataAndDump.java` cut the Ghidra step down to **~1 min** P-code export + **~3 min** C emission. For other DRM-free executables, the full Ghidra pipeline (`FixNoReturn.java`, `ResolveJumpTables.java`, `FixEntries.java`, `DumpPcode.java`) remains available automatically as a fallback.
* **One-command installer & packager (`quick-install.sh`):**
  * Auto-detects game files across common locations (Steam, SteamCMD, DepotDownloader, GOG `innoextract`, `~/Downloads`, `~/Games`, or an existing `.app`), checks for SteamStub `.bind` DRM (offering to back up `FalloutNV.exe` to `FalloutNV.exe.og` and strip the DRM using official Steamless CLI + Mono on demand), verifies the executable SHA-256, installs missing Homebrew dependencies (`ghidra`, `unicorn`, `cmake`, `ffmpeg`, plus `mono` if needed), caches codecs/objects/translations under `~/Library/Caches/fnv-macos/`, moves game data into `Fallout New Vegas.app/Contents/Resources/GameData/`, converts `.bik` cutscenes to `.mp4` via `ffmpeg`, ad-hoc signs the bundle, and optionally wraps it in a `.dmg` (`--dmg`).
* **Additional codebase changes:**
  * **Optional Steamworks bridge & Overlay launcher (Steam builds only):** `upstream/recomp/host/shims_steam.c` loads Valve's official ARM64 `libsteam_api.dylib` (bundled only for Steam builds, omitted for GOG or `--no-steam`) to bridge `steam_api.dll` (`__thiscall` proxies for `ISteamUser`, `ISteamUtils`, `ISteamUserStats`, `ISteamApps`, and `ISteamFriends`, plus `SteamAPI_ManualDispatch_*` callbacks) for Steam achievements and status, with clean offline fallback. `macos/FNVSteamLauncher.c` starts the Mac Steam client silently (`-silent`), waits for global user login (`ConnectToGlobalUser`) before launching the game, and injects `gameoverlayrenderer.dylib` for the Metal Steam Overlay (`Shift+Tab`) and achievement notifications.
  * **User data outside the bundle (`FNV_USER_DIR`):** updates in `upstream/recomp/host/shims_files.c` and `shims_win.c` (`SHGetFolderPathA`) route `UserDocuments` (saves, `FALLOUT.INI`, `FalloutPrefs.ini`) to `~/Library/Application Support/FalloutNV/UserDocuments`, with logs in `~/Library/Logs/FalloutNV/fnv.log`.
  * **macOS 14+ Metal compatibility (`d3d9_metal.m`):** guarded `copts.mathMode = MTLMathModeSafe` with `@available(macOS 15.0, iOS 18.0, *)` so the port builds and runs cleanly on macOS 14 (Sonoma) and newer.
  * **Build & test suite updates (`tools/build.py`, `tools/app_icon.py`, `tests/`):** updated build scripts and native/host test suite for the macOS target.

---

## Requirements & Supported Builds

* **Apple Silicon Mac (`arm64`)** running **macOS 14 (Sonoma)** or later.
* **Xcode Command Line Tools** (`xcode-select --install`) and **Homebrew**.
* **Your own PC copy of *Fallout: New Vegas*:**
  * **GOG (precomputed symbols in `symbols/fnv/`):**
    * File: `FalloutNV.exe`
    * SHA-256: `89e7020487e80f20ddc92ea641c4433b2c6839a82f45a076e414d167d11dd0fe`
    * Builds launch `FalloutNewVegas` directly and completely standalone — no Steam launch, no Steam Overlay, and no `libsteam_api.dylib`.
  * **Steam (precomputed symbols in `symbols/fnv-steam/`):**
    * Original `FalloutNV.exe` (SteamStub v2.1 DRM): `3a87f92f011e5dc9179ddf733cf08be2b39ea6e5b7a8a9e3a9a72dafcc1b104d`
    * Unpacked via Steamless CLI (`v3.1.0.5` + Mono): `19406942e48724d797300c4ea6be9ac69a32f670b8c35db09279a2258422739f`
    * When `quick-install.sh` detects SteamStub DRM, it warns you and asks for confirmation (or pass `--unpack-drm`) to automatically install `mono` (via Homebrew if missing), download the official [Steamless](https://github.com/atom0s/Steamless) CLI release (`v3.1.0.5`, verified by SHA-256), back up the original file to `FalloutNV.exe.og`, strip the DRM, and compile using `symbols/fnv-steam/`.
    * **Steam Achievements & Overlay:** for Steam builds, `quick-install.sh` also fetches Valve's official ARM64 `libsteam_api.dylib` (from Steamworks.NET 20.1.0, verified by SHA-256) into `Contents/Frameworks/` and bundles `FalloutNewVegasLauncher` so double-clicking `Fallout New Vegas.app` automatically starts the Mac Steam client (if installed) and enables achievements, Steam status, and the Steam Overlay (`Shift+Tab`). Pass `--no-steam` at build time to omit Steam integration, or set `FNV_STEAM_NO_OVERLAY=1` / `FNV_STEAM_DISABLE=1` at runtime.
  * **Epic Games Store / other DRM-free builds:** if the SHA-256 differs from the GOG and Steam builds above, `quick-install.sh` automatically falls back to full Ghidra auto-analysis (slower, and unsupported builds may require address adjustments if the binary layout differs).

---

## Obtaining the Windows Game Files on macOS

Because *Fallout: New Vegas* is a Windows-only release on Steam and GOG, you can fetch or extract the game files directly on your Mac using any of the methods below. All output paths shown here are auto-detected by `quick-install.sh`.

### Option 1: Steam

> **AppID note:** `22380` is the standard global edition; use `22490` instead if your Steam account owns the regional PCR edition.

#### Method A — `steamcmd` (recommended)

```sh
brew install --cask steamcmd
steamcmd +@sSteamCmdForcePlatformType windows +login <YOUR_STEAM_USERNAME> +app_update 22380 validate +quit
```

*This downloads the game (along with any DLCs owned by your account) directly into `~/Library/Application Support/Steam/steamapps/common/Fallout New Vegas` (or `~/Steam/steamapps/common/Fallout New Vegas`), both of which `quick-install.sh` auto-detects. Pass `+force_install_dir "$HOME/Downloads/Fallout New Vegas"` before `+login` if you prefer a separate folder.*

#### Method B — `DepotDownloader`

```sh
brew tap steamre/tools
brew install depotdownloader
depotdownloader -app 22380 -os windows -username <YOUR_STEAM_USERNAME> \
  -dir "$HOME/Downloads/Fallout New Vegas"
```

*If you omit `-dir`, DepotDownloader places files under `./depots/22380/<manifest>/` (`~/depots/22380/` and `~/Downloads/depots/22380/` are also auto-detected).*

#### Method C — Steam Client Console

1. Open the hidden Console tab in the desktop Steam client:
   ```sh
   open "steam://open/console"
   ```
2. Download the base Windows depots (plus any DLC depots you own — check Depot IDs on SteamDB if needed):
   ```text
   download_depot 22380 22381
   download_depot 22380 22382
   ```
3. Steam saves each depot separately under:
   `~/Library/Application Support/Steam/steamapps/content/app_22380/depot_*/`
   Merge the contents of those `depot_*` folders into `~/Downloads/Fallout New Vegas/` so `FalloutNV.exe` and `Data/` sit together in one folder.

### Option 2: GOG Offline Installer (`innoextract`)

If you downloaded the GOG offline backup installer (`setup_fallout_new_vegas_*.exe` and its `.bin` parts) to `~/Downloads/`:

```sh
brew install innoextract
innoextract -d "$HOME/Downloads/Fallout New Vegas" ~/Downloads/setup_fallout_new_vegas_*.exe
```

`innoextract` extracts the game files into `~/Downloads/Fallout New Vegas/app/` (containing `FalloutNV.exe` and `Data/`), which `quick-install.sh` auto-detects directly.

---

## Quick Install

```sh
# Auto-detect game files (Downloads, Steam, SteamCMD, DepotDownloader, innoextract)
./quick-install.sh

# Or pass an explicit path
./quick-install.sh "/path/to/Fallout New Vegas"
```

To skip the confirmation prompt when stripping SteamStub DRM, or to wrap the app in a drag-to-Applications `.dmg`:

```sh
./quick-install.sh --unpack-drm --dmg
```

> **Note on disk usage:** to avoid duplicating ~10 GB on disk, `quick-install.sh` **moves** the game files from the source folder into `~/Applications/Fallout New Vegas.app/Contents/Resources/GameData/`. Translation and object caches are stored in `~/Library/Caches/fnv-macos/`.

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
