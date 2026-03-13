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

# ── Helpers ────────────────────────────────────────────────────

get_size() {
    du -sh "$1" 2>/dev/null | awk '{print $1}'
}

get_size_bytes() {
    du -sk "$1" 2>/dev/null | awk '{print $1 * 1024}'
}

bytes_human() {
    local b=$1
    if [ "$b" -gt 1073741824 ]; then printf "%.1f GB" $(echo "$b/1073741824" | bc -l)
    elif [ "$b" -gt 1048576 ]; then printf "%.1f MB" $(echo "$b/1048576" | bc -l)
    elif [ "$b" -gt 1024 ]; then printf "%.0f KB" $(echo "$b/1024" | bc -l)
    else printf "%d B" "$b"; fi
}

print_header() {
    clear
    echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}${BOLD}  ║           🧹  Mac Cleanup Tool  🧹                  ║${RESET}"
    echo -e "${CYAN}${BOLD}  ╚══════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${MAGENTA}${BOLD}  ▶ $1${RESET}"
    echo -e "${DIM}  ────────────────────────────────────────────────────────${RESET}"
}

# ── Item Registry ──────────────────────────────────────────────

declare -a LABELS PATHS SIZES CATEGORIES TYPES SELECTED
INDEX=0

# Types: path | npm | yarn | pnpm | composer | gradle | pip | gem | pod | brew | docker
add_item() {
    local category="$1"
    local label="$2"
    local path="$3"
    local type="${4:-path}"

    local exists=0
    local size="0B"

    case "$type" in
        npm)
            if command -v npm &>/dev/null; then
                size=$(npm cache verify 2>/dev/null | grep "Cache verified" | awk '{print $NF}' || get_size "$HOME/.npm")
                size=$(get_size "$HOME/.npm")
                [ -n "$size" ] && exists=1
            fi
            ;;
        brew)
            if command -v brew &>/dev/null; then
                exists=1; size="~varies"
            fi
            ;;
        docker)
            if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
                exists=1; size="~varies"
            fi
            ;;
        pod)
            if command -v pod &>/dev/null && [ -d "$path" ]; then
                size=$(get_size "$path"); exists=1
            fi
            ;;
        *)
            if [ -e "$path" ]; then
                size=$(get_size "$path")
                [ -n "$size" ] && [ "$size" != "0B" ] && [ "$size" != "  0B" ] && exists=1
            fi
            ;;
    esac

    if [ "$exists" = "1" ]; then
        CATEGORIES[$INDEX]="$category"
        LABELS[$INDEX]="$label"
        PATHS[$INDEX]="$path"
        SIZES[$INDEX]="$size"
        TYPES[$INDEX]="$type"
        SELECTED[$INDEX]=1
        INDEX=$((INDEX + 1))
    fi
}

# ── Scan ──────────────────────────────────────────────────────

scan() {
    print_header
    echo -e "${YELLOW}  🔍  Scanning your Mac...${RESET}"
    echo -e "${DIM}  This may take a few seconds.${RESET}"
    echo ""

    # ── Package Managers ──
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

    # ── Editors & IDEs ──
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

    # ── Browsers ──
    add_item "🌐 Browsers"  "Arc Cache"             "$HOME/Library/Caches/Arc"                                                      path
    add_item "🌐 Browsers"  "Arc App Cache"         "$HOME/Library/Application Support/Arc/User Data/Default/Cache"                 path
    add_item "🌐 Browsers"  "Chrome Cache"          "$HOME/Library/Caches/Google/Chrome"                                           path
    add_item "🌐 Browsers"  "Chrome App Cache"      "$HOME/Library/Application Support/Google/Chrome/Default/Cache"                 path
    add_item "🌐 Browsers"  "Firefox Cache"         "$HOME/Library/Caches/Firefox"                                                  path
    add_item "🌐 Browsers"  "Safari Cache"          "$HOME/Library/Caches/com.apple.Safari"                                         path
    add_item "🌐 Browsers"  "Brave Cache"           "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Default/Cache"   path
    add_item "🌐 Browsers"  "Edge Cache"            "$HOME/Library/Application Support/Microsoft Edge/Default/Cache"                path
    add_item "🌐 Browsers"  "Opera Cache"           "$HOME/Library/Application Support/com.operasoftware.Opera/Cache"               path

    # ── Apps ──
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

    # ── Docker ──
    add_item "🐳 Docker"    "Docker Desktop (prune)" ""  docker

    # ── System ──
    add_item "⚙️  System"    "System Temp Files"     "/private/var/folders"                                  path
    add_item "⚙️  System"    "User .cache folder"    "$HOME/.cache"                                          path
    add_item "⚙️  System"    "System Logs"           "/private/var/log"                                      path
    add_item "⚙️  System"    "User Logs"             "$HOME/Library/Logs"                                    path
    add_item "⚙️  System"    "Crash Reports"         "$HOME/Library/Application Support/CrashReporter"      path
    add_item "⚙️  System"    "Diagnostic Reports"    "$HOME/Library/Logs/DiagnosticReports"                  path
    add_item "⚙️  System"    "iOS Device Backups"    "$HOME/Library/Application Support/MobileSync/Backup"  path
    add_item "⚙️  System"    "Trash"                 "$HOME/.Trash"                                          path

    echo -e "${GREEN}  ✓  Scan complete — found ${BOLD}${INDEX}${RESET}${GREEN} cleanable items${RESET}"
    sleep 0.6
}

# ── Interactive Menu ───────────────────────────────────────────

show_menu() {
    print_header
    echo -e "  ${BOLD}Select items to clean${RESET}  ${DIM}Space/number = toggle · A = all · N = none · Enter = clean · Q = quit${RESET}"
    echo ""

    local current_cat=""
    local total_selected=0

    for i in $(seq 0 $((INDEX - 1))); do
        local cat="${CATEGORIES[$i]}"

        # Print category header when it changes
        if [ "$cat" != "$current_cat" ]; then
            echo -e "  ${BOLD}${BLUE}${cat}${RESET}"
            current_cat="$cat"
        fi

        local checkbox="${RED}[ ]${RESET}"
        if [ "${SELECTED[$i]}" = "1" ]; then
            checkbox="${GREEN}[✓]${RESET}"
            total_selected=$((total_selected + 1))
        fi

        local num=$(printf "%2d" $((i + 1)))
        printf "    ${DIM}%s${RESET} %b  %-42s ${YELLOW}%s${RESET}\n" \
            "$num" "$checkbox" "${LABELS[$i]}" "${SIZES[$i]}"
    done

    echo ""
    echo -e "${DIM}  ──────────────────────────────────────────────────────────${RESET}"
    echo -e "  ${BOLD}${total_selected}/${INDEX}${RESET} items selected"
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

    local success=0
    local failed=0
    local skipped=0

    for i in $(seq 0 $((INDEX - 1))); do
        if [ "${SELECTED[$i]}" = "1" ]; then
            local path="${PATHS[$i]}"
            local label="${LABELS[$i]}"
            local size="${SIZES[$i]}"
            local type="${TYPES[$i]}"
            local result=0

            printf "  ${CYAN}⠿${RESET}  %-45s ${DIM}%s${RESET}" "$label..." "$size"

            case "$type" in
                npm)
                    npm cache clean --force &>/dev/null
                    result=$?
                    ;;
                brew)
                    brew cleanup --prune=all &>/dev/null
                    result=$?
                    ;;
                docker)
                    docker system prune -af --volumes &>/dev/null
                    result=$?
                    ;;
                *)
                    if [ -e "$path" ]; then
                        rm -rf "$path" 2>/dev/null
                        result=$?
                    else
                        skipped=$((skipped + 1))
                        printf "\r  ${DIM}–${RESET}  %-45s ${DIM}skipped${RESET}\n" "$label"
                        continue
                    fi
                    ;;
            esac

            if [ "$result" = "0" ]; then
                printf "\r  ${GREEN}✓${RESET}  %-45s ${YELLOW}freed${RESET}\n" "$label"
                success=$((success + 1))
            else
                printf "\r  ${RED}✗${RESET}  %-45s ${DIM}failed (permission?)${RESET}\n" "$label"
                failed=$((failed + 1))
            fi
        fi
    done

    echo ""
    echo -e "${DIM}  ──────────────────────────────────────────────────────────${RESET}"
    echo ""
    echo -e "  ${GREEN}${BOLD}✓ Done!${RESET}"
    echo -e "  ${GREEN}${success} cleaned${RESET}  ${RED}${failed} failed${RESET}  ${DIM}${skipped} skipped${RESET}"
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

    scan
    interactive_select
    confirm
    clean
}

main
