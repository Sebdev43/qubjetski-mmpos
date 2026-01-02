#!/bin/bash

set -e

UPSTREAM_URL="https://github.com/jtskxx/Jetski-Qubic-Pool/releases/download/latest/qubjetski.PPLNS-latest.tar.gz"
OUTPUT_NAME="qubjetski-latest_mmpos.tar.gz"
WORK_DIR="build_temp"

echo "=== Building qubjetski mmpOS package ==="

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

echo "Downloading upstream miner..."
curl -L -o "$WORK_DIR/upstream.tar.gz" "$UPSTREAM_URL"

echo "Extracting upstream archive..."
cd "$WORK_DIR"
tar -xzf upstream.tar.gz

MINER_DIR=$(find . -maxdepth 1 -type d ! -name '.' | head -1)
if [[ -z "$MINER_DIR" ]]; then
    MINER_DIR="qubjetski"
    mkdir -p "$MINER_DIR"
    mv upstream.tar.gz /tmp/
    tar -xzf /tmp/upstream.tar.gz -C "$MINER_DIR" --strip-components=0 2>/dev/null || \
    mv * "$MINER_DIR/" 2>/dev/null || true
fi

cd ..

echo "Adding mmpOS files..."
cp mmp-external.conf "$WORK_DIR/$MINER_DIR/"
cp mmp-stats.sh "$WORK_DIR/$MINER_DIR/"
cp start_mmpos.sh "$WORK_DIR/$MINER_DIR/"
chmod +x "$WORK_DIR/$MINER_DIR/mmp-stats.sh"
chmod +x "$WORK_DIR/$MINER_DIR/start_mmpos.sh"
chmod +x "$WORK_DIR/$MINER_DIR/qli-Client" 2>/dev/null || true

echo "Creating final archive..."
cd "$WORK_DIR"
tar -czf "../$OUTPUT_NAME" -C "$MINER_DIR" .
cd ..

rm -rf "$WORK_DIR"

echo "=== Build complete: $OUTPUT_NAME ==="
ls -lh "$OUTPUT_NAME"
