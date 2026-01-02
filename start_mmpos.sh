#!/bin/bash
# mmpOS launcher for qubjetski

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

BASE_SETTINGS=$(jq -r '.ClientSettings' appsettings_global.json)

POOL_URL="wss://pplns.jtskxpool.ai/ws/${WALLET}"

SETTINGS=$(echo "$BASE_SETTINGS" | jq \
    --arg pool "$POOL_URL" \
    --arg alias "$ALIAS" \
    --argjson gpu "$GPU" \
    --argjson cpu "$CPU" \
    --argjson threads "$CPU_THREADS" \
    '.poolAddress = $pool | .alias = $alias | .trainer.gpu = $gpu | .trainer.cpu = $cpu | .trainer.cpuThreads = $threads')

if [[ "$CPU" == "true" && "$GPU" == "false" ]]; then
    SETTINGS=$(echo "$SETTINGS" | jq 'del(.idling)')
fi

echo "{\"ClientSettings\":$SETTINGS}" | jq . > appsettings.json

echo "=========================================="
echo "  QUBJETSKI - mmpOS Launcher"
echo "=========================================="
echo "Wallet: $WALLET"
echo "Alias: $ALIAS"
echo "GPU: $GPU | CPU: $CPU (threads: $CPU_THREADS)"
echo "Pool: $POOL_URL"
echo "=========================================="

chmod +x qli-Client 2>/dev/null

exec ./qli-Client
