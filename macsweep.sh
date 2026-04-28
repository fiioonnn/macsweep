#!/bin/bash

# ╔══════════════════════════════════════════════════════════════╗
# ║              🧹  Mac Cleanup Tool                           ║
# ║              github.com/fionn                               ║
# ╚══════════════════════════════════════════════════════════════╝

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Configuration ──────────────────────────────────────────────
VERSION="1.1.0"
GITHUB_REPO="fiioonnn/macsweep"
GITHUB_RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/macsweep.sh"
GITHUB_API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
INSTALL_PATH="/usr/local/bin/macsweep"
UPDATE_TMPFILE=""

# ── Helpers ────────────────────────────────────────────────────

bytes_human() {
    local b=$1
    if [ "$b" -gt 1073741824 ]; then printf "%.1f GB" $(echo "$b/1073741824" | bc -l)
    elif [ "$b" -gt 1048576 ]; then printf "%.1f MB" $(echo "$b/1048576" | bc -l)
    elif [ "$b" -gt 1024 ]; then printf "%.0f KB" $(echo "$b/1024" | bc -l)
    else printf "%d B" "$b"; fi
}

get_size_info() {
    # Returns "<human>|<bytes>" for a path
    local kb
    kb=$(du -sk "$1" 2>/dev/null | awk '{print $1}')
    [ -z "$kb" ] && kb=0
    local bytes=$((kb * 1024))
    local human
    human=$(bytes_human "$bytes")
    echo "${human}|${bytes}"
}

# Spinner frames used by both scan and clean async helpers
SPINNER_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

# Per-section scan state
SCAN_SECTION=""
SCAN_SECTION_FOUND=0
SCAN_SECTION_BYTES=0
SCAN_TOTAL_FOUND=0
SCAN_TOTAL_BYTES=0
SCAN_SPINNER_PID=""

# Kill stray background processes so we never leak spinner subshells.
cleanup_on_exit() {
    [ -n "$SCAN_SPINNER_PID" ] && kill "$SCAN_SPINNER_PID" 2>/dev/null
    [ -n "$UPDATE_TMPFILE" ] && rm -f "$UPDATE_TMPFILE"
    [ -t 1 ] && printf '\033[?25h'
}
trap cleanup_on_exit EXIT

scan_begin_section() {
    scan_end_section
    SCAN_SECTION="$1"
    SCAN_SECTION_FOUND=0
    SCAN_SECTION_BYTES=0

    # Background heartbeat — animates while sequential du calls block the main process
    (
        local i=0
        while true; do
            printf "\r\033[K  ${CYAN}%s${RESET}  Scanning %s..." \
                "${SPINNER_FRAMES[$((i % 10))]}" "$1"
            i=$((i + 1))
            sleep 0.1
        done
    ) &
    SCAN_SPINNER_PID=$!
}

scan_end_section() {
    if [ -n "$SCAN_SPINNER_PID" ]; then
        kill "$SCAN_SPINNER_PID" 2>/dev/null
        wait "$SCAN_SPINNER_PID" 2>/dev/null
        SCAN_SPINNER_PID=""
    fi

    [ -z "$SCAN_SECTION" ] && return
    if [ "$SCAN_SECTION_FOUND" -gt 0 ]; then
        local human noun
        human=$(bytes_human "$SCAN_SECTION_BYTES")
        if [ "$SCAN_SECTION_FOUND" = "1" ]; then noun="item"; else noun="items"; fi
        printf "\r\033[K  ${GREEN}✓${RESET}  %s ${DIM}— %d %s · %s${RESET}\n" \
            "$SCAN_SECTION" "$SCAN_SECTION_FOUND" "$noun" "$human"
    else
        printf "\r\033[K"
    fi
    SCAN_SECTION=""
}

# Run a clean command in the background while animating the line in foreground.
# Args: <bar> <label> <size> -- <cmd...>
# Returns the command's exit code.
run_animated_clean() {
    local bar="$1" label="$2" size="$3"
    shift 3
    "$@" &>/dev/null &
    local pid=$!
    local start_ts
    start_ts=$(date +%s)
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        local elapsed=$(( $(date +%s) - start_ts ))
        local time_str=""
        [ "$elapsed" -ge 3 ] && time_str=" ${DIM}(${elapsed}s)${RESET}"
        printf "\r\033[K  %s  ${CYAN}%s${RESET}  %-38s ${DIM}%s${RESET}%b" \
            "$bar" "${SPINNER_FRAMES[$((i % 10))]}" "${label}..." "$size" "$time_str"
        i=$((i + 1))
        sleep 0.1
    done
    wait "$pid"
    return $?
}

draw_progress_bar() {
    local current=$1 total=$2
    local width=18
    local filled=0 pct=0
    if [ "$total" -gt 0 ]; then
        filled=$((current * width / total))
        pct=$((current * 100 / total))
    fi
    local empty=$((width - filled))
    local bar="" i
    for ((i=0; i<filled; i++)); do bar="${bar}█"; done
    for ((i=0; i<empty; i++)); do bar="${bar}░"; done
    printf "${CYAN}[%s]${RESET} ${BOLD}%3d%%${RESET} ${DIM}%d/%d${RESET}" "$bar" "$pct" "$current" "$total"
}

print_header() {
    # Clear screen + scrollback (xterm CSI 3J) so leftover lines never bleed through
    printf '\033[H\033[2J\033[3J'
    echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}${BOLD}  ║           🧹  Mac Cleanup Tool  🧹                   ║${RESET}"
    echo -e "${CYAN}${BOLD}  ╚══════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${MAGENTA}${BOLD}  ▶ $1${RESET}"
    echo -e "${DIM}  ────────────────────────────────────────────────────────${RESET}"
}

# ── Update check ───────────────────────────────────────────────

check_for_update_bg() {
    [ "${MACSWEEP_NO_UPDATE_CHECK:-0}" = "1" ] && return
    command -v curl &>/dev/null || return
    UPDATE_TMPFILE=$(mktemp)
    (
        local response latest
        response=$(curl -sL --max-time 3 "$GITHUB_API_URL" 2>/dev/null)
        latest=$(printf '%s' "$response" | grep -m1 '"tag_name"' \
            | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v?([^"]+)".*/\1/')
        if [ -n "$latest" ] && [ "$latest" != "$VERSION" ]; then
            if [ "$(printf '%s\n%s\n' "$VERSION" "$latest" | sort -V | tail -1)" = "$latest" ]; then
                echo "$latest" > "$UPDATE_TMPFILE"
            fi
        fi
    ) &
    disown 2>/dev/null || true
}

get_update_version() {
    [ -z "$UPDATE_TMPFILE" ] && return
    [ ! -s "$UPDATE_TMPFILE" ] && return
    cat "$UPDATE_TMPFILE"
}

# ── Install / update / uninstall ───────────────────────────────

is_installed() {
    [ -x "$INSTALL_PATH" ]
}

# Copy a source file to INSTALL_PATH, using sudo if needed
write_to_install_path() {
    local src="$1"
    local dest_dir
    dest_dir="$(dirname "$INSTALL_PATH")"
    if [ -w "$dest_dir" ] || { [ -e "$INSTALL_PATH" ] && [ -w "$INSTALL_PATH" ]; }; then
        cp "$src" "$INSTALL_PATH" && chmod +x "$INSTALL_PATH"
    else
        echo -e "  ${DIM}sudo required to write to ${dest_dir}${RESET}"
        sudo cp "$src" "$INSTALL_PATH" && sudo chmod +x "$INSTALL_PATH"
    fi
}

# Resolve where this script's source lives (or download a fresh copy)
resolve_source() {
    local out="$1"
    if [ -f "$0" ] && [ "$0" != "$INSTALL_PATH" ] && head -1 "$0" 2>/dev/null | grep -q '^#!/bin/bash'; then
        cp "$0" "$out"
        return 0
    fi
    if ! command -v curl &>/dev/null; then
        echo -e "  ${RED}✗${RESET}  curl is required to download macsweep"
        return 1
    fi
    echo -e "  ${CYAN}↓${RESET}  Downloading latest from GitHub..."
    if ! curl -sLf --max-time 30 "$GITHUB_RAW_URL" -o "$out"; then
        echo -e "  ${RED}✗${RESET}  Download failed"
        return 1
    fi
    if ! head -1 "$out" 2>/dev/null | grep -q '^#!/bin/bash'; then
        echo -e "  ${RED}✗${RESET}  Downloaded file looks invalid"
        return 1
    fi
    return 0
}

install_wizard() {
    print_header
    print_section "Install macsweep"
    echo ""

    if is_installed; then
        echo -e "  ${YELLOW}Already installed at ${BOLD}${INSTALL_PATH}${RESET}"
        local current
        current=$("$INSTALL_PATH" --version 2>/dev/null | awk '{print $NF}')
        [ -n "$current" ] && echo -e "  ${DIM}Currently: ${current}${RESET}"
        echo ""
        echo -ne "  Reinstall? ${DIM}[y/N]:${RESET} "
        read -r ans
        [[ ! "$ans" =~ ^[Yy] ]] && { echo -e "  ${YELLOW}Cancelled.${RESET}"; echo ""; exit 0; }
    fi

    echo -e "  Will install ${BOLD}macsweep v${VERSION}${RESET} to ${BOLD}${INSTALL_PATH}${RESET}"
    echo -e "  ${DIM}Then you can run ${BOLD}macsweep${RESET}${DIM} from any terminal.${RESET}"
    echo ""
    echo -ne "  Continue? ${DIM}[Y/n]:${RESET} "
    read -r ans
    if [[ "$ans" =~ ^[Nn] ]]; then
        echo -e "  ${YELLOW}Cancelled.${RESET}"; echo ""; exit 0
    fi

    local tmp
    tmp=$(mktemp)
    if ! resolve_source "$tmp"; then
        rm -f "$tmp"; exit 1
    fi

    echo -e "  ${CYAN}→${RESET}  Installing to ${INSTALL_PATH}"
    if ! write_to_install_path "$tmp"; then
        echo -e "  ${RED}✗${RESET}  Install failed"
        rm -f "$tmp"; exit 1
    fi
    rm -f "$tmp"

    echo ""
    echo -e "  ${GREEN}${BOLD}✓ Installed!${RESET}"
    echo -e "  Run ${BOLD}macsweep${RESET} anytime to clean your Mac."
    echo -e "  ${DIM}Other commands:${RESET} ${BOLD}macsweep update${RESET} ${DIM}·${RESET} ${BOLD}macsweep uninstall${RESET} ${DIM}·${RESET} ${BOLD}macsweep help${RESET}"
    echo ""
}

self_update() {
    print_header
    print_section "Updating macsweep"
    echo ""

    local tmp
    tmp=$(mktemp)
    if ! resolve_source "$tmp"; then
        rm -f "$tmp"; exit 1
    fi

    local target="$INSTALL_PATH"
    if ! is_installed; then
        echo -e "  ${YELLOW}macsweep is not installed yet — installing instead.${RESET}"
    fi

    echo -e "  ${CYAN}→${RESET}  Replacing ${target}"
    if ! write_to_install_path "$tmp"; then
        echo -e "  ${RED}✗${RESET}  Update failed"
        rm -f "$tmp"; exit 1
    fi
    rm -f "$tmp"

    local new_version
    new_version=$("$INSTALL_PATH" --version 2>/dev/null | awk '{print $NF}')
    [ -z "$new_version" ] && new_version="latest"

    echo ""
    echo -e "  ${GREEN}${BOLD}✓ Updated to ${new_version}!${RESET}"
    echo ""
}

uninstall_macsweep() {
    print_header
    print_section "Uninstall macsweep"
    echo ""

    if ! is_installed; then
        echo -e "  ${YELLOW}Not installed at ${INSTALL_PATH}${RESET}"
        echo ""
        exit 0
    fi

    echo -ne "  Remove ${BOLD}${INSTALL_PATH}${RESET}? ${DIM}[y/N]:${RESET} "
    read -r ans
    [[ ! "$ans" =~ ^[Yy] ]] && { echo -e "  ${YELLOW}Cancelled.${RESET}"; echo ""; exit 0; }

    if [ -w "$(dirname "$INSTALL_PATH")" ]; then
        rm -f "$INSTALL_PATH"
    else
        sudo rm -f "$INSTALL_PATH"
    fi

    echo ""
    echo -e "  ${GREEN}✓ Uninstalled${RESET}"
    echo ""
}

offer_install_after_clean() {
    [ "$0" = "$INSTALL_PATH" ] && return
    is_installed && return

    echo -e "${DIM}  ──────────────────────────────────────────────────────────${RESET}"
    echo ""
    echo -e "  ${BOLD}Install macsweep globally?${RESET}"
    echo -e "  ${DIM}So you can run ${BOLD}macsweep${RESET}${DIM} from any terminal — no curl needed.${RESET}"
    echo -ne "  Install now? ${DIM}[Y/n]:${RESET} "
    read -r ans
    if [[ ! "$ans" =~ ^[Nn] ]]; then
        local tmp
        tmp=$(mktemp)
        if resolve_source "$tmp" && write_to_install_path "$tmp"; then
            echo ""
            echo -e "  ${GREEN}${BOLD}✓ Installed to ${INSTALL_PATH}${RESET}"
            echo -e "  ${DIM}Run ${BOLD}macsweep${RESET}${DIM} anytime.${RESET}"
        else
            echo -e "  ${RED}✗ Install failed.${RESET}"
        fi
        rm -f "$tmp"
        echo ""
    fi
}

show_help() {
    echo ""
    echo -e "${BOLD}macsweep v${VERSION}${RESET} — Mac Cleanup Tool"
    echo ""
    echo -e "${BOLD}Usage:${RESET}"
    echo "    macsweep              Run interactive cleanup"
    echo "    macsweep install      Install macsweep globally to ${INSTALL_PATH}"
    echo "    macsweep update       Update to latest version from GitHub"
    echo "    macsweep uninstall    Remove macsweep from system"
    echo "    macsweep version      Print version"
    echo "    macsweep help         Show this help"
    echo ""
    echo -e "${BOLD}Environment:${RESET}"
    echo "    MACSWEEP_NO_UPDATE_CHECK=1   Skip the GitHub update check on startup"
    echo ""
    echo -e "${BOLD}Repo:${RESET} https://github.com/${GITHUB_REPO}"
    echo ""
}

# ── Item Registry ──────────────────────────────────────────────

declare -a LABELS PATHS SIZES SIZES_BYTES CATEGORIES TYPES SELECTED
INDEX=0

# Types: path | clear | npm | yarn | pnpm | composer | gradle | pip | gem | pod | brew | docker
add_item() {
    local category="$1"
    local label="$2"
    local path="$3"
    local type="${4:-path}"

    local exists=0
    local size="0B"
    local size_bytes=0
    local info

    case "$type" in
        npm)
            if command -v npm &>/dev/null; then
                info=$(get_size_info "$HOME/.npm")
                size="${info%|*}"
                size_bytes="${info#*|}"
                exists=1
            fi
            ;;
        brew)
            if command -v brew &>/dev/null; then
                exists=1; size="~varies"; size_bytes=0
            fi
            ;;
        docker)
            if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
                exists=1; size="~varies"; size_bytes=0
            fi
            ;;
        pod)
            if command -v pod &>/dev/null && [ -d "$path" ]; then
                info=$(get_size_info "$path")
                size="${info%|*}"
                size_bytes="${info#*|}"
                exists=1
            fi
            ;;
        clear)
            if [ -d "$path" ]; then
                info=$(get_size_info "$path")
                size="${info%|*}"
                size_bytes="${info#*|}"
                [ "$size_bytes" -gt 0 ] && exists=1
            fi
            ;;
        *)
            if [ -e "$path" ]; then
                info=$(get_size_info "$path")
                size="${info%|*}"
                size_bytes="${info#*|}"
                [ "$size_bytes" -gt 0 ] && exists=1
            fi
            ;;
    esac

    if [ "$exists" = "1" ]; then
        CATEGORIES[$INDEX]="$category"
        LABELS[$INDEX]="$label"
        PATHS[$INDEX]="$path"
        SIZES[$INDEX]="$size"
        SIZES_BYTES[$INDEX]="$size_bytes"
        TYPES[$INDEX]="$type"
        SELECTED[$INDEX]=1
        INDEX=$((INDEX + 1))

        SCAN_SECTION_FOUND=$((SCAN_SECTION_FOUND + 1))
        SCAN_SECTION_BYTES=$((SCAN_SECTION_BYTES + size_bytes))
        SCAN_TOTAL_FOUND=$((SCAN_TOTAL_FOUND + 1))
        SCAN_TOTAL_BYTES=$((SCAN_TOTAL_BYTES + size_bytes))
    fi
}

# ── Scan ──────────────────────────────────────────────────────

scan() {
    print_header
    echo -e "${YELLOW}  🔍  Scanning your Mac...${RESET}"
    echo -e "${DIM}  This may take a few seconds — large folders take longer.${RESET}"
    echo ""

    scan_begin_section "📦 Package Managers"
    add_item "📦 Package Managers" "npm Cache"              "$HOME/.npm"                                    npm
    add_item "📦 Package Managers" "Yarn Cache"             "$HOME/.yarn/cache"                             path
    add_item "📦 Package Managers" "pnpm Store"             "$HOME/.pnpm-store"                             path
    add_item "📦 Package Managers" "Composer Cache"         "$HOME/.composer/cache"                         path
    add_item "📦 Package Managers" "Gradle Cache"           "$HOME/.gradle/caches"                          path
    add_item "📦 Package Managers" "Maven Cache"            "$HOME/.m2/repository"                          path
    add_item "📦 Package Managers" "pip Cache"              "$HOME/Library/Caches/pip"                      path
    add_item "📦 Package Managers" "gem Cache"              "$HOME/.gem"                                    path
    add_item "📦 Package Managers" "CocoaPods Cache"        "$HOME/Library/Caches/CocoaPods"                path
    add_item "📦 Package Managers" "Homebrew Cache"         "$(brew --cache 2>/dev/null)"                   path
    add_item "📦 Package Managers" "Homebrew Logs"          "$(brew --prefix 2>/dev/null)/var/log"          path
    add_item "📦 Package Managers" "Rust Cargo Registry"    "$HOME/.cargo/registry"                         path
    add_item "📦 Package Managers" "Go Module Cache"        "$HOME/go/pkg/mod/cache"                        path
    add_item "📦 Package Managers" "pub (Flutter/Dart)"     "$HOME/.pub-cache"                              path

    scan_begin_section "💻 Editors & IDEs"
    add_item "💻 Editors & IDEs"   "VS Code WorkspaceStorage"   "$HOME/Library/Application Support/Code/User/workspaceStorage"      path
    add_item "💻 Editors & IDEs"   "VS Code Cache"               "$HOME/Library/Application Support/Code/Cache"                      path
    add_item "💻 Editors & IDEs"   "VS Code CrashReports"        "$HOME/Library/Application Support/Code/logs"                       path
    add_item "💻 Editors & IDEs"   "Cursor WorkspaceStorage"     "$HOME/Library/Application Support/Cursor/User/workspaceStorage"    path
    add_item "💻 Editors & IDEs"   "Cursor Cache"                "$HOME/Library/Application Support/Cursor/Cache"                    path
    add_item "💻 Editors & IDEs"   "Cursor GPU Cache"            "$HOME/Library/Application Support/Cursor/GPUCache"                 path
    add_item "💻 Editors & IDEs"   "JetBrains Logs"              "$HOME/Library/Logs/JetBrains"                                      path
    add_item "💻 Editors & IDEs"   "JetBrains Caches"            "$HOME/Library/Caches/JetBrains"                                    path
    add_item "💻 Editors & IDEs"   "Xcode DerivedData"           "$HOME/Library/Developer/Xcode/DerivedData"                         path
    add_item "💻 Editors & IDEs"   "Xcode Archives"              "$HOME/Library/Developer/Xcode/Archives"                            path
    add_item "💻 Editors & IDEs"   "Xcode iOS DeviceSupport"     "$HOME/Library/Developer/Xcode/iOS DeviceSupport"                   path
    add_item "💻 Editors & IDEs"   "Xcode watchOS DeviceSupport" "$HOME/Library/Developer/Xcode/watchOS DeviceSupport"               path
    add_item "💻 Editors & IDEs"   "Simulator Caches"            "$HOME/Library/Developer/CoreSimulator/Caches"                      path
    add_item "💻 Editors & IDEs"   "Simulator Devices (unused)"  "$HOME/Library/Developer/CoreSimulator/Devices"                     path

    scan_begin_section "🌐 Browsers"
    add_item "🌐 Browsers"  "Arc Cache"             "$HOME/Library/Caches/Arc"                                                      path
    add_item "🌐 Browsers"  "Arc App Cache"         "$HOME/Library/Application Support/Arc/User Data/Default/Cache"                 path
    add_item "🌐 Browsers"  "Chrome Cache"          "$HOME/Library/Caches/Google/Chrome"                                           path
    add_item "🌐 Browsers"  "Chrome App Cache"      "$HOME/Library/Application Support/Google/Chrome/Default/Cache"                 path
    add_item "🌐 Browsers"  "Firefox Cache"         "$HOME/Library/Caches/Firefox"                                                  path
    add_item "🌐 Browsers"  "Safari Cache"          "$HOME/Library/Caches/com.apple.Safari"                                         path
    add_item "🌐 Browsers"  "Brave Cache"           "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Default/Cache"   path
    add_item "🌐 Browsers"  "Edge Cache"            "$HOME/Library/Application Support/Microsoft Edge/Default/Cache"                path
    add_item "🌐 Browsers"  "Opera Cache"           "$HOME/Library/Application Support/com.operasoftware.Opera/Cache"               path

    scan_begin_section "🖥️  Apps"
    add_item "🖥️  Apps"      "Claude Cache"          "$HOME/Library/Application Support/Claude/Cache"           path
    add_item "🖥️  Apps"      "Claude Code Cache"     "$HOME/Library/Application Support/Claude/Code Cache"       path
    add_item "🖥️  Apps"      "Claude GPU Cache"      "$HOME/Library/Application Support/Claude/GPUCache"         path
    add_item "🖥️  Apps"      "Slack Cache"           "$HOME/Library/Application Support/Slack/Cache"             path
    add_item "🖥️  Apps"      "Slack Logs"            "$HOME/Library/Application Support/Slack/logs"              path
    add_item "🖥️  Apps"      "Discord Cache"         "$HOME/Library/Application Support/discord/Cache"           path
    add_item "🖥️  Apps"      "Spotify Cache"         "$HOME/Library/Caches/com.spotify.client"                   path
    add_item "🖥️  Apps"      "Figma Cache"           "$HOME/Library/Application Support/Figma/Cache"             path
    add_item "🖥️  Apps"      "Postman Cache"         "$HOME/Library/Application Support/Postman/Cache"           path
    add_item "🖥️  Apps"      "ClickUp Cache"         "$HOME/Library/Application Support/ClickUp/Cache"           path
    add_item "🖥️  Apps"      "Zoom Cache"            "$HOME/Library/Application Support/zoom.us/Cache"           path
    add_item "🖥️  Apps"      "Teams Cache"           "$HOME/Library/Application Support/Microsoft/Teams/Cache"   path
    add_item "🖥️  Apps"      "Notion Cache"          "$HOME/Library/Application Support/Notion/Cache"            path
    add_item "🖥️  Apps"      "Linear Cache"          "$HOME/Library/Application Support/Linear/Cache"            path
    add_item "🖥️  Apps"      "Raycast Cache"         "$HOME/Library/Application Support/com.raycast.macos/Cache" path
    add_item "🖥️  Apps"      "1Password Cache"       "$HOME/Library/Caches/com.1password.1password"              path
    add_item "🖥️  Apps"      "Voicemod Data"         "$HOME/Library/Application Support/VoicemodV3"              path

    scan_begin_section "🐳 Docker"
    add_item "🐳 Docker"    "Docker Desktop (prune)" ""  docker

    scan_begin_section "⚙️  System"
    add_item "⚙️  System"    "System Temp Files"     "/private/var/folders"                                  path
    add_item "⚙️  System"    "User .cache folder"    "$HOME/.cache"                                          path
    add_item "⚙️  System"    "System Logs"           "/private/var/log"                                      path
    add_item "⚙️  System"    "User Logs"             "$HOME/Library/Logs"                                    path
    add_item "⚙️  System"    "Crash Reports"         "$HOME/Library/Application Support/CrashReporter"      path
    add_item "⚙️  System"    "Diagnostic Reports"    "$HOME/Library/Logs/DiagnosticReports"                  path
    add_item "⚙️  System"    "iOS Device Backups"    "$HOME/Library/Application Support/MobileSync/Backup"  path

    scan_end_section

    echo ""
    local total_human
    total_human=$(bytes_human "$SCAN_TOTAL_BYTES")
    if [ "$SCAN_TOTAL_FOUND" -gt 0 ]; then
        echo -e "  ${GREEN}${BOLD}✓ Found ${SCAN_TOTAL_FOUND} cleanable items${RESET}  ${DIM}·${RESET}  ${YELLOW}${BOLD}${total_human}${RESET}"
    else
        echo -e "  ${GREEN}${BOLD}✓ Nothing to clean — your Mac is already tidy.${RESET}"
    fi
    sleep 0.8
}

# ── Sensitive items prompt ─────────────────────────────────────

prompt_sensitive_items() {
    print_header
    print_section "Personal files"
    echo ""
    echo -e "  ${YELLOW}⚠️  These contain YOUR personal data — once deleted they're gone.${RESET}"
    echo ""

    local trash_path="$HOME/.Trash"
    if [ -d "$trash_path" ] && [ -n "$(ls -A "$trash_path" 2>/dev/null)" ]; then
        local info size bytes
        info=$(get_size_info "$trash_path")
        size="${info%|*}"
        bytes="${info#*|}"
        echo -ne "  Empty Trash ${YELLOW}(${size})${RESET}?           ${DIM}[y/N]:${RESET} "
        read -r ans
        if [[ "$ans" =~ ^[Yy] ]]; then
            CATEGORIES[$INDEX]="🗑️  Personal"
            LABELS[$INDEX]="Trash"
            PATHS[$INDEX]="$trash_path"
            SIZES[$INDEX]="$size"
            SIZES_BYTES[$INDEX]="$bytes"
            TYPES[$INDEX]="clear"
            SELECTED[$INDEX]=1
            INDEX=$((INDEX + 1))
        fi
    fi

    local dl_path="$HOME/Downloads"
    if [ -d "$dl_path" ] && [ -n "$(ls -A "$dl_path" 2>/dev/null)" ]; then
        local info size bytes
        info=$(get_size_info "$dl_path")
        size="${info%|*}"
        bytes="${info#*|}"
        echo -ne "  Clear Downloads folder ${YELLOW}(${size})${RESET}? ${DIM}[y/N]:${RESET} "
        read -r ans
        if [[ "$ans" =~ ^[Yy] ]]; then
            CATEGORIES[$INDEX]="🗑️  Personal"
            LABELS[$INDEX]="Downloads"
            PATHS[$INDEX]="$dl_path"
            SIZES[$INDEX]="$size"
            SIZES_BYTES[$INDEX]="$bytes"
            TYPES[$INDEX]="clear"
            SELECTED[$INDEX]=1
            INDEX=$((INDEX + 1))
        fi
    fi
}

# ── Interactive Menu ───────────────────────────────────────────

show_menu() {
    print_header

    local upd
    upd=$(get_update_version)
    if [ -n "$upd" ]; then
        echo -e "  ${YELLOW}${BOLD}⬆ Update available:${RESET} ${DIM}v${VERSION} →${RESET} ${BOLD}${YELLOW}v${upd}${RESET}  ${DIM}— press ${BOLD}u${RESET}${DIM} to update now${RESET}"
        echo ""
    fi

    echo -e "  ${BOLD}Select items to clean${RESET}"
    echo -e "  ${DIM}Number = toggle · A = all · N = none · Enter = clean · Q = quit${RESET}"
    echo ""

    local current_cat=""
    local total_selected=0
    local selected_bytes=0

    for i in $(seq 0 $((INDEX - 1))); do
        local cat="${CATEGORIES[$i]}"
        local sb="${SIZES_BYTES[$i]:-0}"

        if [ "$cat" != "$current_cat" ]; then
            [ -n "$current_cat" ] && echo ""
            echo -e "  ${BOLD}${BLUE}${cat}${RESET}"
            current_cat="$cat"
        fi

        local checkbox="${RED}[ ]${RESET}"
        if [ "${SELECTED[$i]}" = "1" ]; then
            checkbox="${GREEN}[✓]${RESET}"
            total_selected=$((total_selected + 1))
            selected_bytes=$((selected_bytes + sb))
        fi

        local num
        num=$(printf "%2d" $((i + 1)))
        printf "    ${DIM}%s${RESET} %b  %-38s ${YELLOW}%s${RESET}\n" \
            "$num" "$checkbox" "${LABELS[$i]}" "${SIZES[$i]}"
    done

    echo ""
    echo -e "${DIM}  ──────────────────────────────────────────────────────────${RESET}"
    local sel_human
    sel_human=$(bytes_human "$selected_bytes")
    echo -e "  ${BOLD}${total_selected}/${INDEX}${RESET} selected  ${DIM}·${RESET}  ${BOLD}${YELLOW}${sel_human}${RESET} ${DIM}to free${RESET}"
    echo ""
}

interactive_select() {
    while true; do
        show_menu
        echo -ne "  ${BOLD}Choice: ${RESET}"
        read -r input

        case "$input" in
            [Qq])
                echo ""
                echo -e "${YELLOW}  Bye! Nothing was deleted.${RESET}"
                echo ""
                exit 0
                ;;
            [Aa])
                for i in $(seq 0 $((INDEX - 1))); do SELECTED[$i]=1; done
                ;;
            [Nn])
                for i in $(seq 0 $((INDEX - 1))); do SELECTED[$i]=0; done
                ;;
            [Uu])
                if [ -n "$(get_update_version)" ]; then
                    self_update
                    exit 0
                fi
                ;;
            "")
                break
                ;;
            *)
                for num in $(echo "$input" | tr ',' ' '); do
                    if [[ "$num" =~ ^[0-9]+$ ]]; then
                        local idx=$((num - 1))
                        if [ "$idx" -ge 0 ] && [ "$idx" -lt "$INDEX" ]; then
                            if [ "${SELECTED[$idx]}" = "1" ]; then
                                SELECTED[$idx]=0
                            else
                                SELECTED[$idx]=1
                            fi
                        fi
                    fi
                done
                ;;
        esac
    done
}

# ── Confirm ────────────────────────────────────────────────────

confirm() {
    print_header
    print_section "Items to be deleted"
    echo ""

    local count=0
    for i in $(seq 0 $((INDEX - 1))); do
        if [ "${SELECTED[$i]}" = "1" ]; then
            echo -e "  ${RED}✕${RESET}  ${LABELS[$i]}  ${YELLOW}(${SIZES[$i]})${RESET}"
            count=$((count + 1))
        fi
    done

    if [ "$count" = "0" ]; then
        echo -e "${YELLOW}  Nothing selected. Exiting.${RESET}"
        echo ""
        exit 0
    fi

    echo ""
    echo -e "${DIM}  ──────────────────────────────────────────────────────────${RESET}"
    echo ""
    echo -ne "  ${BOLD}${RED}Delete these ${count} items? (yes/no): ${RESET}"
    read -r confirm_input

    if [[ "$confirm_input" != "yes" && "$confirm_input" != "y" ]]; then
        echo ""
        echo -e "${YELLOW}  Cancelled. Nothing was deleted.${RESET}"
        echo ""
        exit 0
    fi
}

# ── Clean ──────────────────────────────────────────────────────

clean() {
    print_header
    print_section "Cleaning..."
    echo ""

    local total_to_clean=0
    for i in $(seq 0 $((INDEX - 1))); do
        [ "${SELECTED[$i]}" = "1" ] && total_to_clean=$((total_to_clean + 1))
    done

    local success=0 failed=0 skipped=0 processed=0 freed_bytes=0

    for i in $(seq 0 $((INDEX - 1))); do
        if [ "${SELECTED[$i]}" = "1" ]; then
            local path="${PATHS[$i]}"
            local label="${LABELS[$i]}"
            local size="${SIZES[$i]}"
            local size_bytes="${SIZES_BYTES[$i]:-0}"
            local type="${TYPES[$i]}"
            local result=0

            processed=$((processed + 1))
            local bar
            bar=$(draw_progress_bar "$processed" "$total_to_clean")

            case "$type" in
                npm)
                    run_animated_clean "$bar" "$label" "$size" npm cache clean --force
                    result=$?
                    ;;
                brew)
                    run_animated_clean "$bar" "$label" "$size" brew cleanup --prune=all
                    result=$?
                    ;;
                docker)
                    run_animated_clean "$bar" "$label" "$size" docker system prune -af --volumes
                    result=$?
                    ;;
                clear)
                    if [ -d "$path" ]; then
                        run_animated_clean "$bar" "$label" "$size" find "$path" -mindepth 1 -delete
                        result=$?
                    else
                        skipped=$((skipped + 1))
                        printf "\r\033[K  %s  ${DIM}–  %-38s skipped${RESET}\n" "$bar" "$label"
                        continue
                    fi
                    ;;
                *)
                    if [ -e "$path" ]; then
                        run_animated_clean "$bar" "$label" "$size" rm -rf "$path"
                        result=$?
                    else
                        skipped=$((skipped + 1))
                        printf "\r\033[K  %s  ${DIM}–  %-38s skipped${RESET}\n" "$bar" "$label"
                        continue
                    fi
                    ;;
            esac

            if [ "$result" = "0" ]; then
                printf "\r\033[K  %s  ${GREEN}✓${RESET}  %-38s ${YELLOW}freed · %s${RESET}\n" \
                    "$bar" "$label" "$size"
                success=$((success + 1))
                freed_bytes=$((freed_bytes + size_bytes))
            else
                printf "\r\033[K  %s  ${RED}✗${RESET}  %-38s ${DIM}failed (permission?)${RESET}\n" \
                    "$bar" "$label"
                failed=$((failed + 1))
            fi
        fi
    done

    local freed_human
    freed_human=$(bytes_human "$freed_bytes")

    echo ""
    echo -e "${DIM}  ──────────────────────────────────────────────────────────${RESET}"
    echo ""
    echo -e "  ${GREEN}${BOLD}✓ All done!${RESET}"
    echo ""
    echo -e "    ${BOLD}Total freed:${RESET}    ${GREEN}${BOLD}${freed_human}${RESET}  🎉"
    echo -e "    ${BOLD}Cleaned:${RESET}        ${GREEN}${success}${RESET} / ${total_to_clean}"
    [ "$failed" -gt 0 ]  && echo -e "    ${BOLD}Failed:${RESET}         ${RED}${failed}${RESET}"
    [ "$skipped" -gt 0 ] && echo -e "    ${BOLD}Skipped:${RESET}        ${DIM}${skipped}${RESET}"
    echo ""
    echo -e "  ${DIM}💡 Tip: Restart your Mac to fully reclaim all freed space.${RESET}"
    echo ""
}

# ── Main ───────────────────────────────────────────────────────

main() {
    # Check macOS
    if [[ "$OSTYPE" != "darwin"* ]]; then
        echo -e "${RED}  ✗ This script only runs on macOS.${RESET}"
        exit 1
    fi

    case "${1:-}" in
        install|--install)     install_wizard; exit 0 ;;
        update|--update)       self_update; exit 0 ;;
        uninstall|--uninstall) uninstall_macsweep; exit 0 ;;
        version|--version|-v)  echo "macsweep v${VERSION}"; exit 0 ;;
        help|--help|-h)        show_help; exit 0 ;;
        "")                    ;;
        *)
            echo -e "${RED}  Unknown command: $1${RESET}"
            echo ""
            show_help
            exit 1
            ;;
    esac

    check_for_update_bg

    scan
    prompt_sensitive_items
    interactive_select
    confirm
    clean
    offer_install_after_clean

    [ -n "$UPDATE_TMPFILE" ] && rm -f "$UPDATE_TMPFILE"
}

main "$@"
