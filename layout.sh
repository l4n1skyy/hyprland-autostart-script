#!/bin/bash

# --- PATH RESOLUTION ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/layout.conf"
AUTOSTART_FILE="$(realpath "${SCRIPT_DIR}/../autostart.conf")"
LOG_FILE="${SCRIPT_DIR}/layout.log"

# --- CLEAN LOGGING ---
log() {
    local timestamp=$(date +'%H:%M:%S')
    echo "[${timestamp}] [$1] $2" | tee -a "${LOG_FILE}" >&2
}

# --- ENGINE UTILITIES ---
run_hypr() { hyprctl "$@" >> /dev/null 2>&1; }

get_window_data() {
    local class="$1" ws="$2"
    hyprctl clients -j | jq -c ".[] | select((.class | contains(\"$class\")) and .workspace.id == $ws)" | head -n 1
}

# --- INITIALIZATION ---
declare -A ALIAS_MAP
declare -A CMD_MAP
declare -A WS_MAP
declare -A FOCUS_RULES
declare -A PROCESSED_RULES
declare -A WS_GEOMETRY_LOCKED
declare -A WS_GROUP_LOCKED
declare -A JOINED_GROUPS

while read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "$line" ]] && continue
    read -ra args <<< "$line"
    case "${args[0]}" in
        "APP")
            ALIAS_MAP["${args[1]}"]="${args[2]}"
            CMD_MAP["${args[1]}"]="${args[*]:3}"
            ;;
        "RATIO"|"GROUP")
            for app in "${args[@]:2}"; do WS_MAP["$app"]="${args[1]}"; done
            ;;
        "FOCUS")
            if [[ "${args[1]}" =~ ^[0-9]+$ ]]; then
                FOCUS_RULES["${args[1]}"]="${args[2]}"
            else
                local al="${args[1]}"
                FOCUS_RULES["${WS_MAP[$al]:-1}"]="$al"
            fi
            ;;
    esac
done < "${CONFIG_FILE}"

# --- THE REACTIVE CORE ---
process_rule() {
    local type="$1" ws="$2" alias="$3" addr="$4" args=("${@:5}")
    local rule_id="${ws}_${type}_${alias}"

    # If already fully verified and locked, skip completely
    [[ -n "${PROCESSED_RULES[$rule_id]}" ]] && return

    local mon_json=$(hyprctl monitors -j | jq -c ".[] | select(.activeWorkspace.id == $ws)" | head -n 1)
    [[ -z "$mon_json" ]] && mon_json=$(hyprctl monitors -j | jq -c ".[0]")
    local mon_w=$(echo "$mon_json" | jq -r '.width')
    local mon_x=$(echo "$mon_json" | jq -r '.x')
    
    local master_threshold=$((mon_x + 100))

    case "$type" in
        "RATIO")
            local move_dir="${args[0]}"
            local x_pct=$(echo "${args[2]}" | tr -d '%')
            local cur_x=$(hyprctl clients -j | jq -r ".[] | select(.address == \"$addr\") | .at[0]")

            # === MASTER WINDOW LOGIC ('l') ===
            if [[ "$move_dir" == "l" ]]; then
                if [[ "$cur_x" -gt "$master_threshold" ]]; then
                    log "DEBUG-MOVE" "WS $ws: [L-RULE] $alias is at x=$cur_x. Forcing Left."
                    run_hypr dispatch focuswindow "address:$addr"
                    run_hypr dispatch movewindow l
                    return # Exit and wait for next loop to verify
                fi
                
                if [[ -z "${WS_GEOMETRY_LOCKED[$ws]}" ]]; then
                    local tw=$(awk "BEGIN {print int($x_pct * $mon_w / 100)}")
                    log "DEBUG-RESIZE" "WS $ws: Master verified. Resizing $alias to ${tw}px."
                    run_hypr dispatch focuswindow "address:$addr"
                    run_hypr dispatch resizewindowpixel "exact $tw 100%,address:$addr"
                    WS_GEOMETRY_LOCKED[$ws]=1
                    log "OK" "WS $ws: Master Split Locked by $alias"
                fi
                
                PROCESSED_RULES["$rule_id"]=1

            # === SLAVE WINDOW LOGIC ('r') ===
            else
                if [[ "$cur_x" -lt "$master_threshold" ]]; then
                    log "DEBUG-MOVE" "WS $ws: [R-RULE] $alias is at x=$cur_x (Master Spot). Forcing Right."
                    run_hypr dispatch focuswindow "address:$addr"
                    run_hypr dispatch movewindow r
                    return # Exit and wait for next loop to verify
                fi
                
                log "OK" "WS $ws: Slave $alias confirmed on the right."
                PROCESSED_RULES["$rule_id"]=1
            fi
            ;;

        "GROUP")
            if [[ -z "${WS_GROUP_LOCKED[$ws]}" ]]; then
                log "ACTION" "WS $ws: Initializing Group (Anchor: $alias)"
                run_hypr dispatch focuswindow "address:$addr"
                run_hypr dispatch togglegroup
                WS_GROUP_LOCKED[$ws]=1
                JOINED_GROUPS["$addr"]=1
                sleep 0.3
            fi

            local missing=0
            for tail in "${args[@]}"; do
                local t_class="${ALIAS_MAP[$tail]:-$tail}"
                local t_json=$(get_window_data "$t_class" "$ws")
                local t_addr=$(echo "$t_json" | jq -r '.address // empty')
                if [[ -n "$t_addr" ]]; then
                    if [[ -z "${JOINED_GROUPS[$t_addr]}" ]]; then
                        log "ACTION" "WS $ws: Adding $tail to group"
                        run_hypr dispatch focuswindow "address:$t_addr"
                        sleep 0.2
                        for d in l r u d; do run_hypr dispatch moveintogroup "$d"; done
                        JOINED_GROUPS["$t_addr"]=1
                    fi
                else
                    missing=$((missing + 1))
                fi
            done
            [[ $missing -eq 0 ]] && PROCESSED_RULES["$rule_id"]=1
            ;;
    esac

    # --- INSTANT FOCUS ---
    if [[ -n "${PROCESSED_RULES[$rule_id]}" && "${FOCUS_RULES[$ws]}" == "$alias" ]]; then
        log "FOCUS" "WS $ws: Instant focus successfully applied to $alias"
        run_hypr dispatch focuswindow "address:$addr"
    fi
}

# --- MAIN LOOP ---
echo "=== SESSION START: $(date) ===" > "${LOG_FILE}"
start_time=$SECONDS

while true; do
    all_rules_done=true
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "$line" ]] && continue
        read -ra args <<< "$line"
        type="${args[0]}"
        [[ ! "$type" =~ ^(RATIO|GROUP)$ ]] && continue
        
        ws="${args[1]}"
        alias="${args[2]}"
        rule_id="${ws}_${type}_${alias}"
        
        if [[ -z "${PROCESSED_RULES[$rule_id]}" ]]; then
            all_rules_done=false
            class="${ALIAS_MAP[$alias]:-$alias}"
            window_json=$(get_window_data "$class" "$ws")
            if [[ -n "$window_json" ]]; then
                addr=$(echo "$window_json" | jq -r '.address')
                size=$(echo "$window_json" | jq -r '.size[0]')
                [[ "$size" -gt 0 ]] && process_rule "$type" "$ws" "$alias" "$addr" "${args[@]:3}"
            fi
        fi
    done < "${CONFIG_FILE}"

    [[ "$all_rules_done" == "true" ]] || [[ $((SECONDS - start_time)) -gt 80 ]] && break
    sleep 1.5
done

# --- COMPLETION ---
run_hypr dispatch workspace 1
notify-send -u normal -a "Omarchy" "Rice Deployed" "Layout engine finished in $((SECONDS - start_time))s"
log "OK" "Finished."
