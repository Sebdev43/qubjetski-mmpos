#!/usr/bin/env bash

DEVICE_NUM=$1
LOG_FILE=$2
API_PORT=4444

get_bus_ids() {
    local vendor_id="$1"
    local gpu_info_json="/run/gpu-info.json"
    local busids=()

    vendor_id=$(echo "$vendor_id" | tr -d '[:space:]')
    case "$vendor_id" in
        10de) vendor="nvidia" ;;
        1002) vendor="amd_sysfs" ;;
        *)    vendor="intel_sysfs" ;;
    esac

    local bus_ids
    bus_ids=$(jq -r ".device.GPU.${vendor}_details.busid[]" "$gpu_info_json" 2>/dev/null)

    if [[ -z "$bus_ids" ]]; then
        return 1
    fi

    while read -r bus_id; do
        local hex=${bus_id:5:2}
        busids+=($((16#$hex)))
    done <<< "$bus_ids"
    echo "${busids[*]}"
}

get_stats_from_api() {
    local api_response
    api_response=$(curl -s --connect-timeout 2 "http://127.0.0.1:${API_PORT}/api" 2>/dev/null)

    if [[ -z "$api_response" ]] || ! echo "$api_response" | jq . >/dev/null 2>&1; then
        return 1
    fi

    echo "$api_response"
}

get_stats_from_log() {
    if [[ ! -f "$LOG_FILE" ]]; then
        return 1
    fi

    local total_hashrate=0
    local accepted=0
    local rejected=0
    local invalid=0

    local last_stats=$(tail -100 "$LOG_FILE" 2>/dev/null)

    local hashrate_line=$(echo "$last_stats" | grep -iE "(hashrate|it/s|sol/s|h/s)" | tail -1)
    if [[ -n "$hashrate_line" ]]; then
        total_hashrate=$(echo "$hashrate_line" | grep -oE "[0-9]+(\.[0-9]+)?" | head -1)
    fi

    local share_line=$(echo "$last_stats" | grep -iE "(accepted|shares|solutions)" | tail -1)
    if [[ -n "$share_line" ]]; then
        accepted=$(echo "$share_line" | grep -oiE "accepted[: ]*[0-9]+" | grep -oE "[0-9]+" | tail -1)
        rejected=$(echo "$share_line" | grep -oiE "rejected[: ]*[0-9]+" | grep -oE "[0-9]+" | tail -1)
        invalid=$(echo "$share_line" | grep -oiE "invalid[: ]*[0-9]+" | grep -oE "[0-9]+" | tail -1)
    fi

    accepted=${accepted:-0}
    rejected=${rejected:-0}
    invalid=${invalid:-0}
    total_hashrate=${total_hashrate:-0}

    echo "{\"hashrate\":$total_hashrate,\"accepted\":$accepted,\"rejected\":$rejected,\"invalid\":$invalid}"
}

build_output() {
    local api_data="$1"
    local busids_array=()
    local hash_array=()
    local accepted=0
    local rejected=0
    local invalid=0

    local nvidia_busids=$(get_bus_ids "10de" 2>/dev/null)
    local amd_busids=$(get_bus_ids "1002" 2>/dev/null)

    if [[ -n "$nvidia_busids" ]]; then
        for id in $nvidia_busids; do
            busids_array+=("$id")
        done
    fi

    if [[ -n "$amd_busids" ]]; then
        for id in $amd_busids; do
            busids_array+=("$id")
        done
    fi

    local has_cpu=false
    if echo "$api_data" | jq -e '.cpu' >/dev/null 2>&1; then
        has_cpu=true
    fi

    if [[ "$has_cpu" == "true" ]] || [[ ${#busids_array[@]} -eq 0 ]]; then
        busids_array=("cpu" "${busids_array[@]}")
    fi

    local gpu_hashrates=$(echo "$api_data" | jq -r '.gpus[]?.hashrate // empty' 2>/dev/null)
    local cpu_hashrate=$(echo "$api_data" | jq -r '.cpu.hashrate // 0' 2>/dev/null)
    local total_hashrate=$(echo "$api_data" | jq -r '.hashrate // .totalHashrate // 0' 2>/dev/null)

    if [[ "$has_cpu" == "true" ]] || [[ ${#busids_array[@]} -eq 1 && "${busids_array[0]}" == "cpu" ]]; then
        if [[ "$cpu_hashrate" != "0" && "$cpu_hashrate" != "null" ]]; then
            hash_array+=("$cpu_hashrate")
        else
            hash_array+=("$total_hashrate")
        fi
    fi

    if [[ -n "$gpu_hashrates" ]]; then
        while read -r hr; do
            hash_array+=("$hr")
        done <<< "$gpu_hashrates"
    fi

    if [[ ${#hash_array[@]} -eq 0 ]]; then
        hash_array+=("$total_hashrate")
    fi

    accepted=$(echo "$api_data" | jq -r '.accepted // .shares.accepted // 0' 2>/dev/null)
    rejected=$(echo "$api_data" | jq -r '.rejected // .shares.rejected // 0' 2>/dev/null)
    invalid=$(echo "$api_data" | jq -r '.invalid // .shares.invalid // 0' 2>/dev/null)

    accepted=${accepted:-0}
    rejected=${rejected:-0}
    invalid=${invalid:-0}

    local busid_json=$(printf '%s\n' "${busids_array[@]}" | jq -R . | jq -s .)
    local hash_json=$(printf '%s\n' "${hash_array[@]}" | jq -R 'tonumber' | jq -s .)

    jq -n \
        --argjson busid "$busid_json" \
        --argjson hash "$hash_json" \
        --arg units "it/s" \
        --arg accepted "$accepted" \
        --arg invalid "$invalid" \
        --arg rejected "$rejected" \
        --arg miner_name "qubjetski" \
        --arg miner_version "latest-pplns" \
        '{
            busid: $busid,
            hash: $hash,
            units: $units,
            air: [$accepted, $invalid, $rejected],
            miner_name: $miner_name,
            miner_version: $miner_version
        }'
}

build_fallback_output() {
    local log_data="$1"

    local hashrate=$(echo "$log_data" | jq -r '.hashrate // 0')
    local accepted=$(echo "$log_data" | jq -r '.accepted // 0')
    local rejected=$(echo "$log_data" | jq -r '.rejected // 0')
    local invalid=$(echo "$log_data" | jq -r '.invalid // 0')

    jq -n \
        --arg hashrate "$hashrate" \
        --arg accepted "$accepted" \
        --arg invalid "$invalid" \
        --arg rejected "$rejected" \
        '{
            busid: ["cpu"],
            hash: [($hashrate | tonumber)],
            units: "it/s",
            air: [$accepted, $invalid, $rejected],
            miner_name: "qubjetski",
            miner_version: "latest-pplns"
        }'
}

api_data=$(get_stats_from_api)
if [[ $? -eq 0 ]] && [[ -n "$api_data" ]]; then
    build_output "$api_data"
    exit 0
fi

log_data=$(get_stats_from_log)
if [[ $? -eq 0 ]] && [[ -n "$log_data" ]]; then
    build_fallback_output "$log_data"
    exit 0
fi

jq -n '{
    busid: ["cpu"],
    hash: [0],
    units: "it/s",
    air: ["0", "0", "0"],
    miner_name: "qubjetski",
    miner_version: "latest-pplns"
}'
