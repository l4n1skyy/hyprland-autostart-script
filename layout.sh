#!/bin/bash

# --- PATH RESOLUTION ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/layout.conf"
AUTOSTART_FILE="$(realpath "${SCRIPT_DIR}/../autostart.conf")"
LOG_FILE="${SCRIPT_DIR}/layout.log"

# --- CLEAN LOGGING ---
# Levels: INFO, MATH, OK, ERROR
log() {
    local timestamp=$(date +'%H:%M:%S')
    echo "[${timestamp}] [$1] $2" | tee -a "${LOG_FILE}"
}

# --- ENGINE UTILITIES ---
run_hypr() { hyprctl "$@" >> /dev/null 2>&1; }

is_ready() {
    local class="$1" ws="$2"
    local window_data=$(hyprctl clients -j | jq -r ".[] | select(.class == \"$class\" and .workspace.id == $ws)")
    [[ -n "$window_data" ]] && [[ $(echo "$window_data" | jq -r '.size[0]') -gt 0 ]]
}

get_address() {
    hyprctl clients -j | jq -r ".[] | select(.class == \"$1\" and .workspace.id == $2) | .address" | head -n 1
}

# --- CORE DEPLOYMENT ---
deploy_workspace() {
    local ws="$1"
    log "INFO" "Deploying Workspace $ws"

    # 1. SYNC: Wait for workspace-specific apps
    local ws_apps=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        read -ra args <<< "$line"
        [[ "${args[0]}" =~ ^(RATIO|GROUP)$ ]] && [[ "${args[1]}" == "$ws" ]] && ws_apps+=($(echo "${ALIAS_MAP[${args[2]}]:-${args[2]}}"))
    done < "${CONFIG_FILE}"

    for app in "${ws_apps[@]}"; do
        local attempt=0
        while ! is_ready "$app" "$ws" && [ $attempt -lt 40 ]; do sleep 0.5; ((attempt++)); done
    done

    # 2. TOPOLOGY: Initial Movement
    run_hypr dispatch workspace "$ws"
    while IFS= read -r line || [[ -n "$line" ]]; do
        read -ra args <<< "$line"
        [[ "${args[0]}" == "RATIO" ]] && [[ "${args[1]}" == "$ws" ]] || continue
        local addr=$(get_address "${ALIAS_MAP[${args[2]}]:-${args[2]}}" "$ws")
        
        run_hypr dispatch focuswindow "address:$addr"
        if [[ "${args[3]}" != "none" ]]; then
            IFS=',' read -ra dirs <<< "${args[3]}"
            for d in "${dirs[@]}"; do run_hypr dispatch movewindow "$d" && sleep 0.1; done
        fi
    done < "${CONFIG_FILE}"

    # 3. GEOMETRY: Pixel-Perfect Resizing
    # Settle time to let the binary tree structure lock
    sleep 0.4 
    read -r mon_w mon_h <<< $(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | "\(.width) \(.height)"' | grep -E '^[0-9]+ [0-9]+$' || hyprctl monitors -j | jq -r '.[0] | "\(.width) \(.height)"')

    while IFS= read -r line || [[ -n "$line" ]]; do
        read -ra args <<< "$line"
        [[ "${args[0]}" == "RATIO" ]] && [[ "${args[1]}" == "$ws" ]] || continue
        local alias="${args[2]}"
        local addr=$(get_address "${ALIAS_MAP[${alias}]:-${alias}}" "$ws")
        local y_pct=$(echo "${args[4]}" | tr -d '%') x_pct=$(echo "${args[5]}" | tr -d '%')

        [[ "$y_pct" == "100" && "$x_pct" == "100" ]] && continue

        local tw=$(awk "BEGIN {print int($x_pct * $mon_w / 100)}")
        local th=$(awk "BEGIN {print int($y_pct * $mon_h / 100)}")

        log "MATH" "$alias: ${x_pct}%x${y_pct}% -> ${tw}x${th}px"
        run_hypr dispatch focuswindow "address:$addr"
        # Small delay to ensure focus is registered by the compositor before resizing
        sleep 0.1
        run_hypr dispatch resizewindowpixel "exact $tw $th,address:$addr"
    done < "${CONFIG_FILE}"

    # 4. GROUPING: Final Tab Management
    while IFS= read -r line || [[ -n "$line" ]]; do
        read -ra args <<< "$line"
        [[ "${args[0]}" == "GROUP" ]] && [[ "${args[1]}" == "$ws" ]] || continue
        local anchor_addr=$(get_address "${ALIAS_MAP[${args[2]}]:-${args[2]}}" "$ws")
        
        run_hypr dispatch focuswindow "address:$anchor_addr"
        sleep 0.2
        run_hypr dispatch togglegroup
        
        for tail in "${args[@]:3}"; do
            local tr_addr=$(get_address "${ALIAS_MAP[$tail]:-$tail}" "$ws")
            run_hypr dispatch focuswindow "address:$tr_addr"
            sleep 0.1
            for d in l r u d; do run_hypr dispatch moveintogroup "$d"; done
        done
        log "OK" "Workspace $ws Grouped."
    done < "${CONFIG_FILE}"
}

# --- INITIALIZATION ---
declare -A ALIAS_MAP
declare -A CMD_MAP
while IFS= read -r line || [[ -n "$line" ]]; do
    read -ra args <<< "$line"
    [[ "${args[0]}" == "APP" ]] && ALIAS_MAP["${args[1]}"]="${args[2]}" && CMD_MAP["${args[1]}"]="${args[*]:3}"
done < "${CONFIG_FILE}"

if [[ "$1" == "--generate" ]]; then
    # ... (Autostart generation logic)
    exit 0
fi

echo "=== SESSION START: $(date) ===" > "${LOG_FILE}"
unique_workspaces=$(grep -E "^(GROUP|RATIO)" "${CONFIG_FILE}" | awk '{print $2}' | sort -nu)

# Process workspaces sequentially to prevent focus stealing
for ws in $unique_workspaces; do
    deploy_workspace "$ws"
done

# Final Focus Pass
while IFS= read -r line || [[ -n "$line" ]]; do
    read -ra args <<< "$line"
    [[ "${args[0]}" == "FOCUS" ]] && run_hypr dispatch workspace "${args[1]}" && run_hypr dispatch focuswindow "class:^${ALIAS_MAP[${args[2]}]:-${args[2]}}$"
done < "${CONFIG_FILE}"

run_hypr dispatch workspace 1
log "OK" "Deployment Complete."
