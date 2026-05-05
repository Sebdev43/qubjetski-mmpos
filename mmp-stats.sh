#!/usr/bin/env bash
# mmpOS stats adapter for qubjetski v3 client

DEVICE_NUM=$1
LOG_FILE=$2

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPSETTINGS="$SCRIPT_DIR/appsettings.json"

API_BIND=$(jq -r '.api.bind // "127.0.0.1:17899"' "$APPSETTINGS" 2>/dev/null)
[[ -z "$API_BIND" || "$API_BIND" == "null" ]] && API_BIND="127.0.0.1:17899"
API_URL="http://${API_BIND}/summary"

get_summary() {
    local response
    response=$(curl -s --connect-timeout 2 "$API_URL" 2>/dev/null)
    if [[ -z "$response" ]] || ! echo "$response" | jq -e . >/dev/null 2>&1; then
        return 1
    fi
    echo "$response"
}

get_gpu_busids() {
    local vendor_id="$1"
    local gpu_info_json="/run/gpu-info.json"
    local vendor

    case "$vendor_id" in
        10de) vendor="nvidia" ;;
        1002) vendor="amd_sysfs" ;;
        *)    vendor="intel_sysfs" ;;
    esac

    local bus_ids
    bus_ids=$(jq -r ".device.GPU.${vendor}_details.busid[]" "$gpu_info_json" 2>/dev/null)
    [[ -z "$bus_ids" ]] && return 1

    while read -r bus_id; do
        local hex=${bus_id:5:2}
        echo $((16#$hex))
    done <<< "$bus_ids"
}

extract_log_hashrate() {
    [[ -f "$LOG_FILE" ]] || return 1
    local last_lines gpu_hs cpu_hs accepted rejected total

    last_lines=$(tail -200 "$LOG_FILE" 2>/dev/null)

    gpu_hs=$(echo "$last_lines" | grep -oP '\[CUDA\].*?\K[0-9]+(?=\s+(avg\s+)?it/s)' | tail -1)
    cpu_hs=$(echo "$last_lines" | grep -E '\[(AVX512|AVX2|SKYLAKE|GENERIC)\]' | grep -oP '\K[0-9]+(?=\s+(avg\s+)?it/s)' | tail -1)

    gpu_hs=${gpu_hs:-0}
    cpu_hs=${cpu_hs:-0}
    total=$((gpu_hs + cpu_hs))

    local shares_line
    shares_line=$(echo "$last_lines" | grep -E "(SHARES|SOLS):" | tail -1)
    accepted=$(echo "$shares_line" | grep -oP '\d+(?=/\d+)' | tail -1)
    rejected=$(echo "$shares_line" | grep -oP 'R:\K\d+')

    accepted=${accepted:-0}
    rejected=${rejected:-0}

    echo "{\"total\":$total,\"gpu\":$gpu_hs,\"cpu\":$cpu_hs,\"accepted\":$accepted,\"rejected\":$rejected}"
}

build_output_from_api() {
    local data="$1"
    local busids=() hashes=()
    local total_hs cpu_hs cpu_running accepted rejected

    total_hs=$(echo "$data" | jq -r '.hashrate.total // 0')
    cpu_hs=$(echo "$data" | jq -r '.cpu.hashrate // .hashrate.cpu // 0')
    cpu_running=$(echo "$data" | jq -r '.cpu.running // false')
    accepted=$(echo "$data" | jq -r '.results.accepted // 0')
    rejected=$(echo "$data" | jq -r '.results.rejected // 0')

    local gpu_lines
    gpu_lines=$(echo "$data" | jq -r '
        .gpu.devices // {} |
        to_entries |
        sort_by((.key | gsub("[^0-9]";"") | tonumber?) // 0) |
        .[] | .value
    ' 2>/dev/null)

    local nvidia_busids amd_busids all_busids
    nvidia_busids=$(get_gpu_busids "10de" 2>/dev/null)
    amd_busids=$(get_gpu_busids "1002" 2>/dev/null)
    all_busids=$(printf '%s\n%s\n' "$nvidia_busids" "$amd_busids" | grep -v '^$')

    local gpu_idx=0
    if [[ -n "$gpu_lines" ]]; then
        while IFS= read -r hs; do
            [[ -z "$hs" ]] && continue
            local busid
            busid=$(echo "$all_busids" | sed -n "$((gpu_idx + 1))p")
            [[ -z "$busid" ]] && busid="$gpu_idx"
            busids+=("$busid")
            hashes+=("$hs")
            gpu_idx=$((gpu_idx + 1))
        done <<< "$gpu_lines"
    fi

    local cpu_active=false
    if [[ "$cpu_running" == "true" ]]; then
        cpu_active=true
    elif (( $(echo "$cpu_hs > 0" | bc -l 2>/dev/null || echo 0) )); then
        cpu_active=true
    fi

    if [[ "$cpu_active" == "true" ]]; then
        busids+=("cpu")
        hashes+=("$cpu_hs")
    fi

    if [[ ${#busids[@]} -eq 0 ]]; then
        busids=("cpu")
        hashes=("$total_hs")
    fi

    local busid_json hash_json
    busid_json=$(printf '%s\n' "${busids[@]}" | jq -R . | jq -s .)
    hash_json=$(printf '%s\n' "${hashes[@]}" | jq -R 'tonumber? // 0' | jq -s .)

    jq -n \
        --argjson busid "$busid_json" \
        --argjson hash "$hash_json" \
        --arg units "hs" \
        --arg accepted "$accepted" \
        --arg rejected "$rejected" \
        --arg miner_name "qubjetski" \
        --arg miner_version "v3-pplns" \
        '{
            busid: $busid,
            hash: $hash,
            units: $units,
            air: [$accepted, "0", $rejected],
            miner_name: $miner_name,
            miner_version: $miner_version
        }'
}

build_output_from_log() {
    local log_data="$1"
    local total gpu_hs cpu_hs accepted rejected

    total=$(echo "$log_data" | jq -r '.total // 0')
    gpu_hs=$(echo "$log_data" | jq -r '.gpu // 0')
    cpu_hs=$(echo "$log_data" | jq -r '.cpu // 0')
    accepted=$(echo "$log_data" | jq -r '.accepted // 0')
    rejected=$(echo "$log_data" | jq -r '.rejected // 0')

    local busids=() hashes=()

    if [[ "$gpu_hs" -gt 0 ]]; then
        local nvidia_busids amd_busids all_busids
        nvidia_busids=$(get_gpu_busids "10de" 2>/dev/null)
        amd_busids=$(get_gpu_busids "1002" 2>/dev/null)
        all_busids=$(printf '%s\n%s\n' "$nvidia_busids" "$amd_busids" | grep -v '^$')

        if [[ -n "$all_busids" ]]; then
            local gpu_count
            gpu_count=$(echo "$all_busids" | wc -l)
            local per_gpu=$((gpu_hs / gpu_count))
            while IFS= read -r busid; do
                [[ -z "$busid" ]] && continue
                busids+=("$busid")
                hashes+=("$per_gpu")
            done <<< "$all_busids"
        else
            busids+=("0")
            hashes+=("$gpu_hs")
        fi
    fi

    if [[ "$cpu_hs" -gt 0 ]]; then
        busids+=("cpu")
        hashes+=("$cpu_hs")
    fi

    if [[ ${#busids[@]} -eq 0 ]]; then
        busids=("cpu")
        hashes=("$total")
    fi

    local busid_json hash_json
    busid_json=$(printf '%s\n' "${busids[@]}" | jq -R . | jq -s .)
    hash_json=$(printf '%s\n' "${hashes[@]}" | jq -R 'tonumber? // 0' | jq -s .)

    jq -n \
        --argjson busid "$busid_json" \
        --argjson hash "$hash_json" \
        --arg units "hs" \
        --arg accepted "$accepted" \
        --arg rejected "$rejected" \
        --arg miner_name "qubjetski" \
        --arg miner_version "v3-pplns" \
        '{
            busid: $busid,
            hash: $hash,
            units: $units,
            air: [$accepted, "0", $rejected],
            miner_name: $miner_name,
            miner_version: $miner_version
        }'
}

api_data=$(get_summary)
if [[ -n "$api_data" ]]; then
    build_output_from_api "$api_data"
    exit 0
fi

log_data=$(extract_log_hashrate)
if [[ -n "$log_data" ]]; then
    build_output_from_log "$log_data"
    exit 0
fi

jq -n '{
    busid: ["cpu"],
    hash: [0],
    units: "hs",
    air: ["0", "0", "0"],
    miner_name: "qubjetski",
    miner_version: "v3-pplns"
}'
