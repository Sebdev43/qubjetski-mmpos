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
- Includes mmpOS integration files (mmp-stats.sh, mmp-external.conf)
- Supports CPU and GPU mining

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
