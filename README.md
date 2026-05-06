# qubjetski-mmpos

Auto-updating mmpOS package for [Jetski Qubic Pool](https://qubic.jetskipool.ai/) PPLNS miner.

## Disclaimer

⚠️ **This is a personal project** created solely for my own use to easily deploy the Jetski Qubic miner on mmpOS.

- I am **not affiliated** with Jetski Pool or the original miner developers
- I do **not own** any of the mining software included in this package
- This repository only provides **mmpOS integration scripts** and automated packaging
- All mining software is downloaded directly from the official [Jetski-Qubic-Pool](https://github.com/jtskxx/Jetski-Qubic-Pool) releases
- For support regarding the miner itself, please refer to the official Jetski channels

**Use at your own risk.**

## Download URL

```
https://github.com/Sebdev43/qubjetski-mmpos/releases/download/latest/qubjetski-latest_mmpos.tar.gz
```

## Features

- Auto-updates daily from upstream [Jetski-Qubic-Pool](https://github.com/jtskxx/Jetski-Qubic-Pool) releases
- Wrapper-side auto-update: rigs pull a new package on miner restart when our release changes (no profile re-import needed)
- Includes mmpOS integration files (mmp-stats.sh, mmp-external.conf)
- Supports CPU and GPU mining

## Auto-update mechanism

mmpOS caches custom miners by SHA-256 of the download URL: once the rig has the package, it never re-downloads from the same URL. To work around this, `start_mmpos.sh` does its own update check at miner restart:

1. Fetches `qubjetski-latest_mmpos.tar.gz.sha256` from this repo's `latest` release (~64 bytes, short timeout)
2. Compares to a local `.installed_hash` file
3. If they differ: downloads the full package, verifies its hash matches, extracts it over the install directory, and re-execs itself with the same arguments

Failure modes (no network, hash mismatch, extraction error) are silent and never block mining — the rig stays on the install it has. First-run on a fresh rig snapshots the current hash without applying anything.

## mmpOS Import JSON

```json
{"miner_profile":{"name":"Qubic-Jetski-PPLNS","coin":"QUBIC","os":"linux","commandline":"./start_mmpos.sh --wallet %wallet_address% --rigid %rig_name%%miner_id% --gpu --cpu --cpu-threads $(nproc) --pplns","miner":"custom","miner_version":"latest","custom_url":"https://github.com/Sebdev43/qubjetski-mmpos/releases/download/latest/qubjetski-latest_mmpos.tar.gz","api_port":0,"platforms":["cpu_intel","cpu_amd","nvidia"]},"pools":[{"url":"pplnsjetski.xyz","port":"443","username":"%wallet_address%.%rig_name%%miner_id%","password":"x","name":"Jetski-Qubic","coin":"QUBIC","ssl":true}]}
```

## Manual Build

```bash
./build.sh
```

## Credits

- Original miner: [jtskxx/Jetski-Qubic-Pool](https://github.com/jtskxx/Jetski-Qubic-Pool)
- Pool: [Jetski Qubic Pool](https://qubic.jetskipool.ai/)
