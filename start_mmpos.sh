#!/bin/bash
# mmpOS launcher for qubjetski PPLNS (v3 client)

# Preserve original args for potential re-exec after self-update
ORIGINAL_ARGS=("$@")

# Self-update configuration
PACKAGE_URL="https://github.com/Sebdev43/qubjetski-mmpos/releases/download/latest/qubjetski-latest_mmpos.tar.gz"
HASH_URL="${PACKAGE_URL}.sha256"
INSTALLED_HASH_FILE=".installed_hash"
UPDATE_LOCK_FILE=".update.lock"
MAX_UPDATE_DEPTH=1

try_self_update() {
    # SCRIPT_DIR must be set before we get here (call site enforces this).
    # Defensive guard: refuse to touch the filesystem with a blank dir.
    [[ -n "$SCRIPT_DIR" ]] || return 0

    # Anti-loop: skip if we already re-exec'd after a successful update
    if [[ "${MMP_UPDATE_DEPTH:-0}" -ge "$MAX_UPDATE_DEPTH" ]]; then
        return 0
    fi

    # Required tools; fail silently if any is absent
    command -v curl >/dev/null 2>&1 || return 0
    command -v flock >/dev/null 2>&1 || return 0
    command -v tar >/dev/null 2>&1 || return 0
    command -v sha256sum >/dev/null 2>&1 || return 0

    # Acquire non-blocking lock; if another instance holds it, skip silently
    exec 200>"$SCRIPT_DIR/$UPDATE_LOCK_FILE" 2>/dev/null || return 0
    if ! flock -n 200; then
        return 0
    fi

    # Fetch advertised hash (small file, short timeout)
    local remote_hash
    remote_hash=$(curl -sfL --max-time 10 "$HASH_URL" 2>/dev/null | tr -d '[:space:]')
    if [[ -z "$remote_hash" || ! "$remote_hash" =~ ^[a-f0-9]{64}$ ]]; then
        return 0
    fi

    # Read locally recorded installed hash (empty on first run)
    local installed_hash=""
    if [[ -f "$SCRIPT_DIR/$INSTALLED_HASH_FILE" ]]; then
        installed_hash=$(cat "$SCRIPT_DIR/$INSTALLED_HASH_FILE" 2>/dev/null | tr -d '[:space:]')
    fi

    # First run on this rig: just snapshot and continue without an update
    if [[ -z "$installed_hash" ]]; then
        echo "$remote_hash" > "$SCRIPT_DIR/$INSTALLED_HASH_FILE" 2>/dev/null
        return 0
    fi

    # No diff -> nothing to do
    if [[ "$remote_hash" == "$installed_hash" ]]; then
        return 0
    fi

    echo "[update] new package available"
    echo "[update]   installed: $installed_hash"
    echo "[update]   remote:    $remote_hash"

    local tmpdir
    tmpdir=$(mktemp -d 2>/dev/null) || return 0
    # shellcheck disable=SC2064
    trap "rm -rf '$tmpdir'" RETURN

    if ! curl -sfL --max-time 120 --retry 2 --retry-delay 5 -o "$tmpdir/pkg.tar.gz" "$PACKAGE_URL"; then
        echo "[update] download failed, keeping current install"
        return 0
    fi

    local size
    size=$(stat --format=%s "$tmpdir/pkg.tar.gz" 2>/dev/null || echo 0)
    if [[ "$size" -lt 1048576 || "$size" -gt 524288000 ]]; then
        echo "[update] downloaded archive size suspicious: $size bytes"
        return 0
    fi

    if ! file "$tmpdir/pkg.tar.gz" 2>/dev/null | grep -q gzip; then
        echo "[update] downloaded file is not a gzip archive"
        return 0
    fi

    local actual_hash
    actual_hash=$(sha256sum "$tmpdir/pkg.tar.gz" | awk '{print $1}')
    if [[ "$actual_hash" != "$remote_hash" ]]; then
        echo "[update] hash mismatch: expected $remote_hash, got $actual_hash"
        return 0
    fi

    # Pre-extract: reject any path-traversal or absolute-path entries
    if tar -tzf "$tmpdir/pkg.tar.gz" 2>/dev/null | grep -qE '(^/|(^|/)\.\./|^~)'; then
        echo "[update] tarball contains suspicious paths, abort"
        return 0
    fi

    mkdir -p "$tmpdir/staged"
    if ! tar -xzf "$tmpdir/pkg.tar.gz" \
            -C "$tmpdir/staged" \
            --no-same-owner --no-same-permissions \
            2>/dev/null; then
        echo "[update] extraction failed"
        return 0
    fi

    # Sanity: the new package must contain the binary and the wrapper itself
    if [[ ! -f "$tmpdir/staged/qubjetski-Client" || ! -f "$tmpdir/staged/start_mmpos.sh" ]]; then
        echo "[update] staging incomplete (missing qubjetski-Client or start_mmpos.sh), abort"
        return 0
    fi

    # Smoke test: the new wrapper must at least pass syntax check
    if ! bash -n "$tmpdir/staged/start_mmpos.sh" 2>/dev/null; then
        echo "[update] new start_mmpos.sh fails bash -n, abort"
        return 0
    fi

    # Backup current install for rollback if the new copy goes wrong mid-flight
    local backup_dir="$SCRIPT_DIR/.backup_pre_update"
    mkdir -p "$backup_dir" 2>/dev/null
    cp -af "$SCRIPT_DIR"/qubjetski-Client \
           "$SCRIPT_DIR"/start_mmpos.sh \
           "$SCRIPT_DIR"/mmp-stats.sh \
           "$SCRIPT_DIR"/appsettings_global.json \
           "$backup_dir"/ 2>/dev/null

    # Apply: copy entire staged tree (including dotfiles) into install dir
    if ! cp -af "$tmpdir/staged/." "$SCRIPT_DIR/" 2>/dev/null; then
        echo "[update] apply failed (filesystem permissions?), restoring backup"
        cp -af "$backup_dir"/. "$SCRIPT_DIR/" 2>/dev/null
        return 0
    fi

    # Post-cp integrity check: critical files still present and non-empty
    if [[ ! -s "$SCRIPT_DIR/qubjetski-Client" ]] \
        || [[ ! -s "$SCRIPT_DIR/start_mmpos.sh" ]] \
        || ! bash -n "$SCRIPT_DIR/start_mmpos.sh" 2>/dev/null; then
        echo "[update] post-apply check failed, restoring backup"
        cp -af "$backup_dir"/. "$SCRIPT_DIR/" 2>/dev/null
        return 0
    fi

    chmod +x "$SCRIPT_DIR/qubjetski-Client" 2>/dev/null
    chmod +x "$SCRIPT_DIR/start_mmpos.sh" 2>/dev/null
    chmod +x "$SCRIPT_DIR/mmp-stats.sh" 2>/dev/null

    # Record new installed hash AFTER all checks pass
    echo "$remote_hash" > "$SCRIPT_DIR/$INSTALLED_HASH_FILE" 2>/dev/null

    echo "[update] applied successfully, re-exec'ing self"

    # Release lock before exec (the new process opens its own)
    flock -u 200 2>/dev/null

    export MMP_UPDATE_DEPTH=$((${MMP_UPDATE_DEPTH:-0} + 1))
    exec "$SCRIPT_DIR/start_mmpos.sh" "${ORIGINAL_ARGS[@]}"
}

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

# Try self-update before touching appsettings or launching the binary
try_self_update

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
