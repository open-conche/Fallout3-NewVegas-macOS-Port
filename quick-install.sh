#!/bin/bash
# Fallout: New Vegas native macOS (Apple Silicon) quick builder & packager.
#
# Recompiles your own PC copy of Fallout: New Vegas (Steam, GOG, or Epic)
# into a standalone Apple Silicon macOS bundle ("Fallout New Vegas.app").
#
# Usage: quick-install.sh [--dmg] [--keep-ghidra] [--unpack-drm] [--no-steam] [game_files_dir]
#   --dmg            also wrap the app in "Fallout New Vegas.dmg"
#   --keep-ghidra    keep the Ghidra project and P-code JSONL after translation
#   --unpack-drm     unattended: allow downloading Steamless + Mono to strip SteamStub DRM
#   --no-steam       keep Steam builds in offline mode (skip Steam launcher, overlay & libsteam_api.dylib)
#   game_files_dir   optional folder containing FalloutNV.exe and Data/
#                    or an existing "Fallout New Vegas.app" bundle.
set -euo pipefail

GOG_EXE_SHA256="89e7020487e80f20ddc92ea641c4433b2c6839a82f45a076e414d167d11dd0fe"
STEAM_OG_EXE_SHA256="3a87f92f011e5dc9179ddf733cf08be2b39ea6e5b7a8a9e3a9a72dafcc1b104d"
STEAM_UNPACKED_EXE_SHA256="19406942e48724d797300c4ea6be9ac69a32f670b8c35db09279a2258422739f"
STEAMLESS_VERSION="v3.1.0.5"
STEAMLESS_URL="https://github.com/atom0s/Steamless/releases/download/v3.1.0.5/Steamless.v3.1.0.5.-.by.atom0s.zip"
STEAMLESS_ZIP_SHA256="e3e2d22e098ff3fb359b2876aa2bed9596f0501e6ff588cbffae90a76d2dc4f5"
STEAMWORKS_URL="https://github.com/rlabrecque/Steamworks.NET/releases/download/20.1.0/Steamworks.NET_20.1.0.unitypackage"
STEAMWORKS_SHA256="3be79e6bdf53c86210267bf39f46362bb839130896006aec26364c5efc37e314"
APP_NAME="Fallout New Vegas"
VOLNAME="$APP_NAME"
DEST_DIR="$HOME/Applications"
CACHE_ROOT="$HOME/Library/Caches/fnv-macos"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Presentation & Styling
# ---------------------------------------------------------------------------
FANCY=no
[ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] && FANCY=yes || true

if [ "$FANCY" = yes ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 256 ]; then
	G1=$'\033[38;5;214m'  G2=$'\033[38;5;220m'  G3=$'\033[38;5;221m'
	G4=$'\033[38;5;222m'  G5=$'\033[38;5;223m'
	GOLD=$'\033[38;5;220m' GREEN=$'\033[38;5;84m' RED=$'\033[38;5;203m'
	CYAN=$'\033[38;5;51m'  BOLD=$'\033[1m' DIM=$'\033[2m' RESET=$'\033[0m'
elif [ "$FANCY" = yes ]; then
	G1=$'\033[93m' G2=$'\033[93m' G3=$'\033[33m' G4=$'\033[37m' G5=$'\033[97m'
	GOLD=$'\033[93m' GREEN=$'\033[92m' RED=$'\033[91m' CYAN=$'\033[96m'
	BOLD=$'\033[1m' DIM=$'\033[2m' RESET=$'\033[0m'
else
	G1= G2= G3= G4= G5= GOLD= GREEN= RED= CYAN= BOLD= DIM= RESET=
fi

SPIN=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
BAR_WIDTH=24

banner() {
	printf '\n'
	printf '  %s███████╗███╗   ██╗██╗   ██╗   ███╗   ███╗ █████╗  ██████╗%s\n' "$G1" "$RESET"
	printf '  %s██╔════╝████╗  ██║██║   ██║   ████╗ ████║██╔══██╗██╔════╝%s\n' "$G2" "$RESET"
	printf '  %s█████╗  ██╔██╗ ██║██║   ██║   ██╔████╔██║███████║██║     %s\n' "$G3" "$RESET"
	printf '  %s██╔══╝  ██║╚██╗██║╚██╗ ██╔╝   ██║╚██╔╝██║██╔══██║██║     %s\n' "$G4" "$RESET"
	printf '  %s██║     ██║ ╚████║ ╚████╔╝    ██║ ╚═╝ ██║██║  ██║╚██████╗%s\n' "$G5" "$RESET"
	printf '  %s╚═╝     ╚═╝  ╚═══╝  ╚═══╝     ╚═╝     ╚═╝╚═╝  ╚═╝ ╚═════╝%s\n' "$G5" "$RESET"
	printf '\n'
	printf '  %sFallout: New Vegas · Metal · Apple Silicon%s\n' "$DIM" "$RESET"
	printf '\n'
}

STEPS_TOTAL=7
STEP=0
step() {
	STEP=$((STEP + 1))
	printf '\n%s◆%s %s[%d/%d]%s %s\n' "$GOLD" "$RESET" "$BOLD" "$STEP" "$STEPS_TOTAL" "$RESET" "$1"
}
ok()   { printf '  %s✔%s %s\n' "$GREEN" "$RESET" "$1"; }
warn() { printf '  %s⚠%s %s\n' "$GOLD" "$RESET" "$1"; }
die() {
	printf '  %s✘ error:%s %s\n' "$RED" "$RESET" "$1" >&2
	shift
	local line
	for line in "$@"; do printf '    %s\n' "$line" >&2; done
	exit 1
}

hsize() {
	awk -v b="${1:-0}" 'BEGIN {
		u[1]="B"; u[2]="KB"; u[3]="MB"; u[4]="GB"; i=1
		while (b >= 1024 && i < 4) { b /= 1024; i++ }
		if (i == 1) printf "%d %s", b, u[i]; else printf "%.1f %s", b, u[i]
	}'
}

du_bytes() {
	local kb
	kb=$(du -sk "$1" 2>/dev/null | awk 'NR==1 {print $1}')
	echo $(( ${kb:-0} * 1024 ))
}

draw_bar() {
	local glyph=$1 label=$2 cur=$3 total=$4
	local pct=0 filled=0 bar='' j=0 tdisp='?'
	if [ "$total" -gt 0 ]; then
		pct=$((cur * 100 / total))
		[ "$pct" -gt 100 ] && pct=100
		tdisp=$(hsize "$total")
	fi
	filled=$((pct * BAR_WIDTH / 100))
	while [ "$j" -lt "$BAR_WIDTH" ]; do
		if [ "$j" -lt "$filled" ]; then bar="${bar}█"; else bar="${bar}░"; fi
		j=$((j + 1))
	done
	printf '\r  %s %s %s%s%s %3d%%  %s%s / %s%s\033[K' \
		"$glyph" "$label" "$GOLD" "$bar" "$RESET" "$pct" \
		"$DIM" "$(hsize "$cur")" "$tdisp" "$RESET"
}

watch_bytes() {
	local pid=$1 label=$2 total=$3
	shift 3
	local i=0 rc=0 cur=0
	printf '\033[?25l'
	while kill -0 "$pid" 2>/dev/null; do
		cur=$("$@" 2>/dev/null || echo 0)
		draw_bar "${CYAN}${SPIN[$((i % 10))]}${RESET}" "$label" "$cur" "$total"
		i=$((i + 1))
		sleep 0.2
	done
	wait "$pid" || rc=$?
	printf '\033[?25h'
	if [ "$rc" -eq 0 ]; then
		[ "$total" -le 0 ] && total=$("$@" 2>/dev/null || echo 0)
		draw_bar "${GREEN}✔${RESET}" "$label" "$total" "$total"
		printf '\n'
	else
		printf '\r  %s✘%s %s failed\033[K\n' "$RED" "$RESET" "$label"
	fi
	return "$rc"
}

run_task() {
	local label=$1
	shift
	if [ "$FANCY" = no ]; then
		echo "==> $label"
		"$@"
		return
	fi
	local i=0 rc=0 pid
	"$@" &
	pid=$!
	printf '\033[?25l'
	while kill -0 "$pid" 2>/dev/null; do
		printf '\r  %s%s%s %s\033[K' "$CYAN" "${SPIN[$((i % 10))]}" "$RESET" "$label"
		i=$((i + 1))
		sleep 0.1
	done
	wait "$pid" || rc=$?
	printf '\033[?25h'
	if [ "$rc" -eq 0 ]; then
		printf '\r  %s✔%s %s\033[K\n' "$GREEN" "$RESET" "$label"
	else
		printf '\r  %s✘%s %s failed\033[K\n' "$RED" "$RESET" "$label"
	fi
	return "$rc"
}

# ---------------------------------------------------------------------------
# Options & System Checks
# ---------------------------------------------------------------------------
WANT_DMG=no
KEEP_GHIDRA=no
UNPACK_DRM=no
NO_STEAM=no
GAME_ARG=""
for arg in "$@"; do
	case "$arg" in
		--dmg) WANT_DMG=yes ;;
		--keep-ghidra) KEEP_GHIDRA=yes ;;
		--unpack-drm) UNPACK_DRM=yes ;;
		--no-steam) NO_STEAM=yes ;;
		*) GAME_ARG="$arg" ;;
	esac
done

banner

if [ "$(uname -sm)" != "Darwin arm64" ]; then
	die "This installer requires an Apple Silicon Mac (arm64)."
fi

OS_VER="$(sw_vers -productVersion)"
OS_MAJOR="$(echo "$OS_VER" | cut -d. -f1)"
if [ "$OS_MAJOR" -lt 14 ]; then
	die "macOS 14 (Sonoma) or newer is required (detected $OS_VER)."
fi

if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find clang >/dev/null 2>&1; then
	die "Apple Command Line Tools / Xcode not found." \
		"Run: xcode-select --install"
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/fnv-install.XXXXXX")"
DEV=""
APP=""
GDATA=""
cleanup() {
	kill $(jobs -p) 2>/dev/null || true
	[ -n "$DEV" ] && hdiutil detach "$DEV" >/dev/null 2>&1 || true
	if [ -n "$TMP" ]; then
		if [ -n "$GDATA" ] && [ -d "$GDATA" ] && [ -n "$(ls -A "$GDATA" 2>/dev/null)" ]; then
			printf '  %s⚠ Note:%s Preserving moved game files at %s\n' "$GOLD" "$RESET" "$APP" >&2
		else
			rm -rf "$TMP"
		fi
	fi
	[ "$FANCY" = yes ] && printf '\033[?25h' || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Step 1: Locate Fallout: New Vegas game files
# ---------------------------------------------------------------------------
step "Locating Fallout: New Vegas game files"

resolve_game_dir() {
	local base="${1%/}" root dir
	for root in "$base" "$base.app"; do
		for dir in \
			"$root" \
			"$root/app" \
			"$root/Fallout New Vegas" \
			"$root/Fallout New Vegas/app" \
			"$root/Fallout New Vegas Ultimate" \
			"$root/steamapps/common/Fallout New Vegas" \
			"$root/Contents/Resources/GameData"; do
			if [ -f "$dir/FalloutNV.exe" ] && [ -f "$dir/Data/FalloutNV.esm" ]; then
				echo "$dir"
				return 0
			fi
		done
	done
	return 1
}

ASSET_SRC=""
if [ -n "$GAME_ARG" ]; then
	ASSET_SRC="$(resolve_game_dir "$GAME_ARG" || true)"
	[ -n "$ASSET_SRC" ] || die "Could not find FalloutNV.exe + Data/FalloutNV.esm in: $GAME_ARG"
else
	CANDIDATES=(
		"/Applications/$APP_NAME.app"
		"$HOME/Applications/$APP_NAME.app"
		"$HOME/Downloads/$APP_NAME.app"
		"$HOME/Downloads/Fallout New Vegas"
		"$HOME/Downloads/Fallout New Vegas Ultimate"
		"$HOME/Downloads/fnv"
		"$HOME/Downloads/app"
		"$HOME/Games/Fallout New Vegas"
		"$HOME/Library/Application Support/Steam/steamapps/common/Fallout New Vegas"
		"$HOME/Steam/steamapps/common/Fallout New Vegas"
		"$HOME/Steam/fnv"
		"$HOME/Documents/Fallout New Vegas"
	)
	shopt -s nullglob
	CANDIDATES+=(
		"$HOME"/Downloads/depots/22380/*
		"$HOME"/depots/22380/*
		"$HOME"/Downloads/depots/22490/*
		"$HOME"/depots/22490/*
	)
	shopt -u nullglob
	for candidate in "${CANDIDATES[@]}"; do
		ASSET_SRC="$(resolve_game_dir "$candidate" || true)"
		[ -n "$ASSET_SRC" ] && break
	done
fi

[ -n "$ASSET_SRC" ] || die "Fallout: New Vegas folder not found." \
	"Pass the path to your Fallout New Vegas folder (containing FalloutNV.exe and Data/):" \
	"  ./quick-install.sh ~/Downloads/\"Fallout New Vegas\""

ok "Found game files at: $ASSET_SRC"

EXE_PATH="$ASSET_SRC/FalloutNV.exe"

has_bind_section() {
	python3 - "$1" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read()
pe = struct.unpack_from('<I', d, 0x3c)[0]
n = struct.unpack_from('<H', d, pe + 6)[0]
o = struct.unpack_from('<H', d, pe + 20)[0]
secs = [d[pe + 24 + o + 40 * i : pe + 24 + o + 40 * i + 8].rstrip(b'\x00') for i in range(n)]
print('yes' if b'.bind' in secs else 'no')
PY
}

unpack_steam_drm() {
	if ! command -v mono >/dev/null 2>&1; then
		command -v brew >/dev/null 2>&1 || die "Homebrew is required to install Mono for Steamless." \
			"Install Homebrew from https://brew.sh and re-run this script."
		run_task "Installing Mono runtime via Homebrew" brew install mono
	fi
	local mono_bin
	mono_bin="$(command -v mono || true)"
	[ -n "$mono_bin" ] || die "Mono runtime not found after installation."

	local steamless_dir="$CACHE_ROOT/steamless/$STEAMLESS_VERSION"
	if [ ! -f "$steamless_dir/Steamless.CLI.exe" ] || [ ! -f "$steamless_dir/Plugins/Steamless.API.dll" ]; then
		local zip_path="$TMP/steamless.zip"
		rm -rf "$steamless_dir"
		mkdir -p "$steamless_dir"
		run_task "Downloading official Steamless ($STEAMLESS_VERSION)" \
			curl -fsSL "$STEAMLESS_URL" -o "$zip_path"
		local zip_sha
		zip_sha="$(shasum -a 256 "$zip_path" | awk '{print $1}')"
		if [ "$zip_sha" != "$STEAMLESS_ZIP_SHA256" ]; then
			rm -rf "$steamless_dir"
			die "Downloaded Steamless archive SHA-256 mismatch." \
				"Expected: $STEAMLESS_ZIP_SHA256" \
				"Got:      $zip_sha"
		fi
		run_task "Extracting Steamless ($STEAMLESS_VERSION)" \
			unzip -qo "$zip_path" -d "$steamless_dir"
		[ -f "$steamless_dir/Steamless.CLI.exe" ] || die "Steamless.CLI.exe missing after extraction."
	else
		ok "Using cached Steamless ($STEAMLESS_VERSION)"
	fi

	if [ ! -f "${EXE_PATH}.og" ]; then
		cp -p "$EXE_PATH" "${EXE_PATH}.og"
		ok "Backed up original executable to $(basename "${EXE_PATH}.og")"
	fi

	local work_dir="$TMP/steamless-work"
	local work_exe="$work_dir/FalloutNV.exe"
	local log_file="$TMP/steamless.log"
	mkdir -p "$work_dir"
	cp "$EXE_PATH" "$work_exe"

	if ! run_task "Removing SteamStub DRM with Steamless CLI (Mono)" \
		bash -c 'MONO_PATH="$1" "$2" "$3" "$4" >"$5" 2>&1' _ \
		"$steamless_dir/Plugins" "$mono_bin" "$steamless_dir/Steamless.CLI.exe" "$work_exe" "$log_file"; then
		cat "$log_file" >&2 || true
		die "Steamless failed to unpack FalloutNV.exe."
	fi

	local unpacked="$work_exe.unpacked.exe"
	[ -f "$unpacked" ] || { cat "$log_file" >&2 || true; die "Steamless did not produce an unpacked executable."; }
	[ "$(has_bind_section "$unpacked")" = no ] || die "Unpacked FalloutNV.exe still contains a .bind section."

	mv "$unpacked" "$EXE_PATH"
	chmod +x "$EXE_PATH"
}

HAS_BIND="$(has_bind_section "$EXE_PATH")"
ACTUAL_SHA="$(shasum -a 256 "$EXE_PATH" | awk '{print $1}')"

if [ "$ACTUAL_SHA" = "$GOG_EXE_SHA256" ] && [ "$HAS_BIND" = no ]; then
	ok "Verified DRM-free GOG FalloutNV.exe (SHA-256 matches precomputed symbols)"
elif [ "$ACTUAL_SHA" = "$STEAM_UNPACKED_EXE_SHA256" ] && [ "$HAS_BIND" = no ]; then
	ok "Verified unpacked Steam FalloutNV.exe (SHA-256 matches precomputed Steam symbols)"
elif [ "$ACTUAL_SHA" = "$STEAM_OG_EXE_SHA256" ] || [ "$HAS_BIND" = yes ]; then
	if [ "$ACTUAL_SHA" = "$STEAM_OG_EXE_SHA256" ]; then
		warn "Detected Steam FalloutNV.exe with SteamStub DRM ($ACTUAL_SHA)"
	else
		warn "SteamStub DRM detected in FalloutNV.exe (.bind section present, $ACTUAL_SHA)"
	fi
	printf '    The static recompiler requires an unencrypted executable.\n'
	printf '    This script can download official Steamless (%s) + Mono (if missing),\n' "$STEAMLESS_VERSION"
	printf '    back up FalloutNV.exe to FalloutNV.exe.og, and strip the DRM automatically.\n'

	if [ "$UNPACK_DRM" != yes ]; then
		if [ -t 0 ]; then
			printf '  %s?%s Remove SteamStub DRM now? [y/N] ' "$CYAN" "$RESET"
			read -r REPLY
			case "$REPLY" in
				[yY]|[yY][eE][sS]|[sS]) UNPACK_DRM=yes ;;
				*) die "Aborted. Cannot statically recompile a SteamStub-packed executable." ;;
			esac
		else
			die "Non-interactive session: re-run interactively or pass --unpack-drm to strip SteamStub DRM."
		fi
	fi

	unpack_steam_drm
	ACTUAL_SHA="$(shasum -a 256 "$EXE_PATH" | awk '{print $1}')"
	if [ "$ACTUAL_SHA" = "$STEAM_UNPACKED_EXE_SHA256" ]; then
		ok "Removed SteamStub DRM (SHA-256 matches precomputed Steam symbols)"
	else
		warn "Removed SteamStub DRM, but unpacked SHA-256 differs ($ACTUAL_SHA)"
	fi
else
	warn "FalloutNV.exe SHA-256 differs from supported GOG/Steam builds ($ACTUAL_SHA)"
fi

# ---------------------------------------------------------------------------
# Step 2: Check and install build tools (Homebrew)
# ---------------------------------------------------------------------------
step "Checking Homebrew tools (ghidra, unicorn, cmake, ffmpeg)"

if ! command -v brew >/dev/null 2>&1; then
	die "Homebrew is required to install Ghidra and Unicorn." \
		"Install from https://brew.sh and re-run this script."
fi

MISSING_BREW=()
for pkg in ghidra unicorn cmake ffmpeg; do
	if ! brew list "$pkg" >/dev/null 2>&1 && ! command -v "$pkg" >/dev/null 2>&1; then
		MISSING_BREW+=("$pkg")
	fi
done

if [ ${#MISSING_BREW[@]} -gt 0 ]; then
	run_task "Installing via Homebrew: ${MISSING_BREW[*]}" brew install "${MISSING_BREW[@]}"
fi

HEADLESS="$(brew --prefix ghidra)/libexec/support/analyzeHeadless"
[ -x "$HEADLESS" ] || die "Ghidra analyzeHeadless not found at $HEADLESS"
UNICORN_PREFIX="$(brew --prefix unicorn)"
[ -f "$UNICORN_PREFIX/lib/libunicorn.a" ] || die "libunicorn.a not found at $UNICORN_PREFIX"
ok "Toolchain ready (Ghidra + Unicorn + CMake + FFmpeg)"

# ---------------------------------------------------------------------------
# Step 3: Build Ogg/Vorbis native codecs (cached)
# ---------------------------------------------------------------------------
step "Preparing native Ogg/Vorbis audio codecs"

CODECS_DIR="$CACHE_ROOT/codecs"
CODEC_PREFIX="$CODECS_DIR/prefix"
if [ -f "$CODEC_PREFIX/codec-manifest.json" ] && \
   python3 -c "import sys; sys.path.insert(0, '$SCRIPT_DIR/tools'); from native_codecs import validate; validate('$CODEC_PREFIX', 'macos')" >/dev/null 2>&1; then
	ok "Using cached macOS Ogg/Vorbis codecs"
else
	run_task "Building pinned Ogg/Vorbis static libraries" \
		python3 "$SCRIPT_DIR/tools/build_codecs.py" macos --out "$CODECS_DIR"
fi

# ---------------------------------------------------------------------------
# Step 4: Translate FalloutNV.exe -> C (Ghidra + emit.py, cached)
# ---------------------------------------------------------------------------
step "Translating FalloutNV.exe to native ARM64 C (cached per executable)"

SHORT_SHA="${ACTUAL_SHA:0:12}"
TRANS_WORK="$CACHE_ROOT/translate-$SHORT_SHA"
GEN_DIR="$TRANS_WORK/generated"
mkdir -p "$TRANS_WORK"

if [ -f "$GEN_DIR/table.c" ] && [ -f "$GEN_DIR/stubs.c" ] && ls "$GEN_DIR"/tu_*.c >/dev/null 2>&1; then
	ok "Using cached translated C sources ($GEN_DIR)"
else
	rm -rf "$GEN_DIR"
	GHIDRA_PROJ="$TRANS_WORK/ghidra"
	GHIDRA_LOG="$TRANS_WORK/ghidra.log"
	PASS_OUT="$TRANS_WORK/passes"
	JSONL="$TRANS_WORK/all.jsonl"
	SCRIPTS="$SCRIPT_DIR/tools/ghidra"
	EXE_NAME="$(basename "$EXE_PATH")"

	mkdir -p "$GHIDRA_PROJ" "$PASS_OUT"
	SYM_DIR=""
	if [ "$ACTUAL_SHA" = "$GOG_EXE_SHA256" ]; then
		SYM_DIR="$SCRIPT_DIR/symbols/fnv"
	elif [ "$ACTUAL_SHA" = "$STEAM_UNPACKED_EXE_SHA256" ]; then
		SYM_DIR="$SCRIPT_DIR/symbols/fnv-steam"
	fi
	if [ -n "$SYM_DIR" ] && [ -f "$SYM_DIR/functions.tsv" ]; then
		ok "Using precomputed function & jump-table metadata ($SYM_DIR)"
		rm -rf "$GHIDRA_PROJ/fnv.gpr" "$GHIDRA_PROJ/fnv.rep"
		run_task "Disassembling & exporting P-code (~1 min, no Ghidra auto-analysis)" \
			env GHIDRA_HEADLESS_MAXMEM=4G "$HEADLESS" "$GHIDRA_PROJ" fnv \
			-import "$EXE_PATH" -noanalysis \
			-scriptPath "$SCRIPTS" \
			-postScript ApplyMetadataAndDump.java "$SYM_DIR" "$JSONL" \
			-log "$GHIDRA_LOG" -scriptlog "$TRANS_WORK/script.log"

		run_task "Emitting C translation units (~3 min)" \
			python3 "$SCRIPT_DIR/tools/translate/emit.py" "$JSONL" "$GEN_DIR" \
			--extra "$SYM_DIR/extra_entries.json"
	else
		if [ -z "${GHIDRA_HEADLESS_MAXMEM:-}" ]; then
			MEM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
			if [ "$MEM_GB" -ge 24 ]; then
				export GHIDRA_HEADLESS_MAXMEM=16G
			elif [ "$MEM_GB" -ge 16 ]; then
				export GHIDRA_HEADLESS_MAXMEM=10G
			else
				export GHIDRA_HEADLESS_MAXMEM=6G
			fi
		fi

		if [ ! -f "$GHIDRA_PROJ/ghidra.done" ]; then
			rm -rf "$GHIDRA_PROJ/fnv.gpr" "$GHIDRA_PROJ/fnv.rep"
			printf '  %sRunning Ghidra import & auto-analysis (heap %s, first run only)...%s\n' "$DIM" "$GHIDRA_HEADLESS_MAXMEM" "$RESET"
			run_task "Ghidra import & analysis ($EXE_NAME)" \
				"$HEADLESS" "$GHIDRA_PROJ" fnv -import "$EXE_PATH" \
				-log "$GHIDRA_LOG" -scriptlog "$TRANS_WORK/script.log"
			touch "$GHIDRA_PROJ/ghidra.done"
		else
			ok "Reusing existing Ghidra project in $GHIDRA_PROJ"
		fi

		run_task "Repairing functions, jump tables & CRT tables (pass 1/2)" \
			"$HEADLESS" "$GHIDRA_PROJ" fnv -process "$EXE_NAME" -noanalysis \
			-scriptPath "$SCRIPTS" \
			-postScript FixNoReturn.java \
			-postScript ResolveJumpTables.java \
			-postScript FixEntries.java "$PASS_OUT" \
			-log "$GHIDRA_LOG"

		run_task "Repairing functions, CRT operation tables & exporting P-code (pass 2/2)" \
			"$HEADLESS" "$GHIDRA_PROJ" fnv -process "$EXE_NAME" -noanalysis \
			-scriptPath "$SCRIPTS" \
			-postScript FixNoReturn.java \
			-postScript ResolveJumpTables.java \
			-postScript ResolveCrtOperationTables.java apply "$PASS_OUT/crt-report.json" "$PASS_OUT/crt-extra.json" \
			-postScript FixEntries.java "$PASS_OUT" \
			-postScript DumpPcode.java "$JSONL" all \
			-log "$GHIDRA_LOG"

		python3 - "$PASS_OUT/extra_entries.json" "$PASS_OUT/crt-extra.json" "$PASS_OUT/merged-extra-entries.json" <<'PY'
import json, sys
merged = {}
for path in sys.argv[1:3]:
    try:
        data = json.load(open(path))
    except FileNotFoundError:
        continue
    for k, vals in data.items():
        merged.setdefault(k, [])
        for v in vals:
            if v not in merged[k]:
                merged[k].append(v)
json.dump(merged, open(sys.argv[3], 'w'))
PY

		run_task "Emitting C translation units" \
			python3 "$SCRIPT_DIR/tools/translate/emit.py" "$JSONL" "$GEN_DIR" \
			--extra "$PASS_OUT/merged-extra-entries.json"
	fi

	if [ "$KEEP_GHIDRA" = no ]; then
		rm -rf "$GHIDRA_PROJ" "$JSONL" "$JSONL.regs.json"
		ok "Cleaned temporary Ghidra project & P-code dump to save disk space"
	fi
fi

# ---------------------------------------------------------------------------
# Step 5: Compile & link Fallout New Vegas.app
# ---------------------------------------------------------------------------
step "Compiling native ARM64 Metal engine & game code"

OBJ_CACHE="$CACHE_ROOT/objects-$SHORT_SHA"
BUILD_OUT="$TMP/build"
mkdir -p "$BUILD_OUT"

STEAM_BUILD_ARGS=()
if [ "$NO_STEAM" != yes ] && [ "$ACTUAL_SHA" != "$GOG_EXE_SHA256" ] && { [ "$ACTUAL_SHA" = "$STEAM_UNPACKED_EXE_SHA256" ] || [ -f "$ASSET_SRC/steam_api.dll" ]; }; then
	SW_DIR="$CACHE_ROOT/steamworks/20.1.0"
	SW_DYLIB="$SW_DIR/libsteam_api.dylib"
	if [ ! -f "$SW_DYLIB" ]; then
		SW_PKG="$TMP/Steamworks.NET_20.1.0.unitypackage"
		SW_EXTRACT="$TMP/steamworks-extract"
		if run_task "Downloading Steamworks.NET 20.1.0 (Valve libsteam_api.dylib)" \
			curl -fsSL --retry 3 "$STEAMWORKS_URL" -o "$SW_PKG"; then
			SW_GOT="$(shasum -a 256 "$SW_PKG" | awk '{print $1}')"
			if [ "$SW_GOT" = "$STEAMWORKS_SHA256" ]; then
				mkdir -p "$SW_DIR" "$SW_EXTRACT"
				tar -xzf "$SW_PKG" -C "$SW_EXTRACT"
				for d in "$SW_EXTRACT"/*; do
					[ -f "$d/asset" ] && [ -f "$d/pathname" ] || continue
					p="$(head -n 1 "$d/pathname")"
					case "$p" in
						*/Plugins/steam_api.bundle/Contents/MacOS/libsteam_api.dylib)
							cp "$d/asset" "$SW_DYLIB"
							chmod 755 "$SW_DYLIB"
							break
							;;
					esac
				done
			else
				warn "Steamworks.NET SHA-256 mismatch ($SW_GOT); building offline without Steam achievements"
			fi
		else
			warn "Failed to download Steamworks.NET; building offline without Steam achievements"
		fi
	else
		ok "Using cached Valve libsteam_api.dylib"
	fi
	if [ -f "$SW_DYLIB" ]; then
		STEAM_APPID="22380"
		if [[ "$ASSET_SRC" == *"/22490/"* ]] || [ -f "$ASSET_SRC/../../appmanifest_22490.acf" ]; then
			STEAM_APPID="22490"
		fi
		STEAM_BUILD_ARGS=(--steam-api-dylib "$SW_DYLIB" --steam-appid "$STEAM_APPID")
		ok "Bundling Steam launcher, Overlay hook & libsteam_api.dylib (AppID $STEAM_APPID)"
	fi
fi

printf '  %sCompiling translation units with Apple Clang (cached incrementally)...%s\n' "$DIM" "$RESET"
python3 "$SCRIPT_DIR/tools/build.py" game \
	--generated "$GEN_DIR" \
	--exe "$EXE_PATH" \
	--codec-prefix "$CODEC_PREFIX" \
	--unicorn-prefix "$UNICORN_PREFIX" \
	--cache "$OBJ_CACHE" \
	--out "$BUILD_OUT" \
	--app-name "$APP_NAME" \
	${STEAM_BUILD_ARGS[@]+"${STEAM_BUILD_ARGS[@]}"} \
	--no-call-trace

APP="$BUILD_OUT/$APP_NAME.app"
[ -d "$APP" ] || die "Expected built bundle not found at $APP"
ok "Compiled $APP_NAME.app"

# ---------------------------------------------------------------------------
# Step 6: Move game files into bundle & convert Bink movies
# ---------------------------------------------------------------------------
step "Moving game files into app bundle & converting intro/cutscene movies"

GDATA="$APP/Contents/Resources/GameData"
mkdir -p "$GDATA"

# If ASSET_SRC is already inside an existing .app's GameData, check if same/different
move_game_files() {
	mv "$ASSET_SRC/FalloutNV.exe" "$GDATA/"
	mv "$ASSET_SRC/Data" "$GDATA/"
	for ini in "$ASSET_SRC"/*.ini; do
		[ -e "$ini" ] && mv "$ini" "$GDATA/"
	done
	[ -d "$ASSET_SRC/NativeMedia" ] && mv "$ASSET_SRC/NativeMedia" "$GDATA/" || true
}

if [ "$FANCY" = yes ]; then
	MOVE_TOTAL=$(du_bytes "$ASSET_SRC")
	move_game_files &
	watch_bytes $! "Moving game files" "$MOVE_TOTAL" du_bytes "$GDATA" \
		|| die "Moving game files failed"
else
	echo "==> Moving game files into $GDATA..."
	move_game_files
fi

# Convert Data/Video/*.bik -> NativeMedia/*.mp4 for native AVFoundation playback
VIDEO_DIR=""
for cand in "$GDATA/Data/Video" "$GDATA/data/video" "$GDATA/Data/video"; do
	[ -d "$cand" ] && { VIDEO_DIR="$cand"; break; }
done

if [ -n "$VIDEO_DIR" ]; then
	mkdir -p "$GDATA/NativeMedia"
	shopt -s nullglob nocaseglob
	BIKS=("$VIDEO_DIR"/*.bik)
	shopt -u nullglob nocaseglob
	if [ ${#BIKS[@]} -gt 0 ]; then
		convert_movies() {
			for bik in "${BIKS[@]}"; do
				base="$(basename "$bik")"
				stem="${base%.*}"
				out_mp4="$GDATA/NativeMedia/$stem.mp4"
				if [ ! -f "$out_mp4" ]; then
					ffmpeg -y -v error -i "$bik" -c:v libx264 -pix_fmt yuv420p -c:a aac -movflags +faststart "$out_mp4" </dev/null || true
				fi
			done
		}
		run_task "Converting ${#BIKS[@]} Bink movie(s) to MP4 for AVFoundation" convert_movies
	fi
fi

mkdir -p "$HOME/Library/Application Support/FalloutNV/UserDocuments" "$HOME/Library/Logs/FalloutNV"

# ---------------------------------------------------------------------------
# Step 7: Ad-hoc sign & finalize
# ---------------------------------------------------------------------------
step "Signing app bundle & finalizing"

sign_bundle() {
	find "$APP" -name "._*" -delete 2>/dev/null || true
	xattr -cr "$APP" 2>/dev/null || true
	codesign --force --deep --sign - "$APP"
}
run_task "Ad-hoc signing $APP_NAME.app" sign_bundle || die "Code signing failed"

mkdir -p "$DEST_DIR"
if [ "$WANT_DMG" = no ]; then
	rm -rf "$DEST_DIR/$APP_NAME.app"
	mv "$APP" "$DEST_DIR/$APP_NAME.app"
	GDATA=""
	ok "Placed $APP_NAME.app in $DEST_DIR"
	printf '\n%s✔ Done!%s %s is ready.\n' "$GREEN$BOLD" "$RESET" "$DEST_DIR/$APP_NAME.app"
	printf '  Double-click it in Applications (or Launchpad/Spotlight) to play.\n'
	printf '  Saves & INIs live in ~/Library/Application Support/FalloutNV/\n\n'
	open -R "$DEST_DIR/$APP_NAME.app" 2>/dev/null || true
	exit 0
fi

STAGE="$TMP/stage"
mkdir -p "$STAGE"
mv "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
TMPDMG="$TMP/rw.dmg"

run_task "Creating disk image" hdiutil create -srcfolder "$STAGE" -volname "$VOLNAME" -fs HFS+ -format UDRW "$TMPDMG" >/dev/null
rm -f "$DEST_DIR/$APP_NAME.dmg"
run_task "Compressing disk image" hdiutil convert "$TMPDMG" -format UDZO -imagekey zlib-level=9 -o "$DEST_DIR/$APP_NAME.dmg" >/dev/null
GDATA=""
ok "Created $DEST_DIR/$APP_NAME.dmg"
open -R "$DEST_DIR/$APP_NAME.dmg" 2>/dev/null || true
