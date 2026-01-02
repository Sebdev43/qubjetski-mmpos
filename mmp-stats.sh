#!/usr/bin/env bash

DEVICE_NUM=$1
LOG_FILE=$2
API_PORT=63005

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
    api_response=$(curl -s --connect-timeout 2 "http://127.0.0.1:${API_PORT}/" 2>/dev/null)

    if [[ -z "$api_response" ]] || ! echo "$api_response" | jq . >/dev/null 2>&1; then
        return 1
    fi

    echo "$api_response"
}

extract_hashrate_from_log() {
    if [[ ! -f "$LOG_FILE" ]]; then
        return 1
    fi

    local last_lines=$(tail -100 "$LOG_FILE" 2>/dev/null)

    local gpu_hs=$(echo "$last_lines" | grep -oP '\[CUDA\].*?(\d+) avg it/s' | tail -1 | grep -oP '\d+(?= avg it/s)')

    local cpu_hs=$(echo "$last_lines" | grep -E "\[(AVX512|AVX2|GENERIC)\]" | grep "avg it/s" | tail -1 | grep -oP '\d+(?= avg it/s)')

    local xmr_hs=$(echo "$last_lines" | grep "\[XMR\]" | grep "avg it/s" | tail -1 | grep -oP '\| \d+ avg it/s' | grep -oP '\d+')

    gpu_hs=${gpu_hs:-0}
    cpu_hs=${cpu_hs:-0}
    xmr_hs=${xmr_hs:-0}

    local total=$((gpu_hs + cpu_hs + xmr_hs))

    local shares_line=$(echo "$last_lines" | grep -E "(SHARES|SOLS):" | tail -1)
    local accepted=$(echo "$shares_line" | grep -oP '\d+(?=/\d+)' | tail -1)
    local rejected=$(echo "$shares_line" | grep -oP 'R:\K\d+')

    accepted=${accepted:-0}
    rejected=${rejected:-0}

    echo "{\"total\":$total,\"gpu\":$gpu_hs,\"cpu\":$cpu_hs,\"xmr\":$xmr_hs,\"accepted\":$accepted,\"rejected\":$rejected}"
}

build_output_from_api() {
    local api_data="$1"
    local busids_array=()
    local hash_array=()

    local total_hs=$(echo "$api_data" | jq -r '.hashrate.total[0] // 0' 2>/dev/null)
    local gpu_hashrates=$(echo "$api_data" | jq -r '.hashrate.threads[][0] // empty' 2>/dev/null)
    local api_busids=$(echo "$api_data" | jq -r '.hwmon.busID[]? // empty' 2>/dev/null)

    if [[ -n "$api_busids" ]]; then
        while read -r busid; do
            if [[ "$busid" != "null" && -n "$busid" ]]; then
                local decimal_bus=$(echo "$busid" | cut -d ":" -f1 | awk '{ printf "%d\n",("0x"$1) }')
                busids_array+=("$decimal_bus")
            fi
        done <<< "$api_busids"
    fi

    if [[ -n "$gpu_hashrates" ]]; then
        while read -r hr; do
            hash_array+=("$hr")
        done <<< "$gpu_hashrates"
    fi

    local has_cpu=false
    if [[ -f "$LOG_FILE" ]]; then
        local cpu_check=$(tail -50 "$LOG_FILE" | grep -cE "\[(AVX512|AVX2|GENERIC|XMR)\]")
        [[ $cpu_check -gt 0 ]] && has_cpu=true
    fi

    if [[ "$has_cpu" == "true" ]]; then
        local cpu_hs=0
        if [[ -f "$LOG_FILE" ]]; then
            local xmr_hs=$(tail -50 "$LOG_FILE" | grep "\[XMR\]" | grep "avg it/s" | tail -1 | grep -oP '\| \d+ avg it/s' | grep -oP '\d+')
            local avx_hs=$(tail -50 "$LOG_FILE" | grep -E "\[(AVX512|AVX2|GENERIC)\]" | grep "avg it/s" | tail -1 | grep -oP '\d+(?= avg it/s)')
            cpu_hs=$((${xmr_hs:-0} + ${avx_hs:-0}))
        fi
        busids_array=("cpu" "${busids_array[@]}")
        hash_array=("$cpu_hs" "${hash_array[@]}")
    fi

    if [[ ${#busids_array[@]} -eq 0 ]]; then
        busids_array=("cpu")
        hash_array=("$total_hs")
    fi

    local busid_json=$(printf '%s\n' "${busids_array[@]}" | jq -R . | jq -s .)
    local hash_json=$(printf '%s\n' "${hash_array[@]}" | jq -R 'tonumber' | jq -s .)

    jq -n \
        --argjson busid "$busid_json" \
        --argjson hash "$hash_json" \
        --arg units "it/s" \
        --arg accepted "0" \
        --arg invalid "0" \
        --arg rejected "0" \
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

build_output_from_log() {
    local log_data="$1"
    local busids_array=()
    local hash_array=()

    local total=$(echo "$log_data" | jq -r '.total // 0')
    local gpu_hs=$(echo "$log_data" | jq -r '.gpu // 0')
    local cpu_hs=$(echo "$log_data" | jq -r '.cpu // 0')
    local xmr_hs=$(echo "$log_data" | jq -r '.xmr // 0')
    local accepted=$(echo "$log_data" | jq -r '.accepted // 0')
    local rejected=$(echo "$log_data" | jq -r '.rejected // 0')

    local cpu_total=$((cpu_hs + xmr_hs))

    if [[ $cpu_total -gt 0 ]]; then
        busids_array+=("cpu")
        hash_array+=("$cpu_total")
    fi

    if [[ $gpu_hs -gt 0 ]]; then
        local nvidia_busids=$(get_bus_ids "10de" 2>/dev/null)
        local amd_busids=$(get_bus_ids "1002" 2>/dev/null)

        if [[ -n "$nvidia_busids" ]] || [[ -n "$amd_busids" ]]; then
            for id in $nvidia_busids $amd_busids; do
                busids_array+=("$id")
            done
            local gpu_count=${#busids_array[@]}
            [[ $cpu_total -gt 0 ]] && gpu_count=$((gpu_count - 1))

            if [[ $gpu_count -gt 0 ]]; then
                local per_gpu=$((gpu_hs / gpu_count))
                for ((i=0; i<gpu_count; i++)); do
                    hash_array+=("$per_gpu")
                done
            fi
        else
            busids_array+=("0")
            hash_array+=("$gpu_hs")
        fi
    fi

    if [[ ${#busids_array[@]} -eq 0 ]]; then
        busids_array=("cpu")
        hash_array=("$total")
    fi

    local busid_json=$(printf '%s\n' "${busids_array[@]}" | jq -R . | jq -s .)
    local hash_json=$(printf '%s\n' "${hash_array[@]}" | jq -R 'tonumber' | jq -s .)

    jq -n \
        --argjson busid "$busid_json" \
        --argjson hash "$hash_json" \
        --arg units "it/s" \
        --arg accepted "$accepted" \
        --arg invalid "0" \
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

api_data=$(get_stats_from_api)
if [[ $? -eq 0 ]] && [[ -n "$api_data" ]] && [[ "$api_data" != "{}" ]]; then
    build_output_from_api "$api_data"
    exit 0
fi

log_data=$(extract_hashrate_from_log)
if [[ $? -eq 0 ]] && [[ -n "$log_data" ]]; then
    build_output_from_log "$log_data"
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
