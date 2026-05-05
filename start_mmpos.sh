#!/bin/bash
# mmpOS launcher for qubjetski PPLNS (v3 client)

WALLET=""
ALIAS=""
GPU=false
CPU=false
CPU_THREADS=$(nproc)
PPLNS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --wallet)
            WALLET="$2"
            shift 2
            ;;
        --rigid)
            ALIAS="$2"
            shift 2
            ;;
        --gpu)
            GPU=true
            shift
            ;;
        --cpu)
            CPU=true
            shift
            ;;
        --cpu-threads)
            CPU_THREADS="$2"
            shift 2
            ;;
        --pplns)
            PPLNS=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

if [[ -z "$WALLET" ]]; then
    echo "ERROR: --wallet is required"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -f "appsettings_global.json" ]]; then
    echo "ERROR: appsettings_global.json not found"
    exit 1
fi

if [[ ! -x "qubjetski-Client" ]] && [[ ! -f "qubjetski-Client" ]]; then
    echo "ERROR: qubjetski-Client binary not found"
    exit 1
fi

jq \
    --arg wallet "$WALLET" \
    --arg alias "$ALIAS" \
    --argjson gpu "$GPU" \
    --argjson cpu "$CPU" \
    --argjson threads "$CPU_THREADS" \
    --argjson pplns "$PPLNS" \
    '.pool.wallet = $wallet |
     .pool.alias = $alias |
     .pool.pps = $pplns |
     .miner.gpu.enabled = $gpu |
     .miner.cpu.enabled = $cpu |
     .miner.cpu.threads = $threads' \
    appsettings_global.json > appsettings.json

echo "=========================================="
echo "  QUBJETSKI PPLNS - mmpOS (v3 client)"
echo "=========================================="
echo "Wallet: $WALLET"
echo "Alias:  $ALIAS"
echo "GPU:    $GPU"
echo "CPU:    $CPU (threads: $CPU_THREADS)"
echo "PPLNS:  $PPLNS"
echo "=========================================="

chmod +x qubjetski-Client 2>/dev/null

exec ./qubjetski-Client -start
