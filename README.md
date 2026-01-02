# qubjetski-mmpos

Auto-updating mmpOS package for [Jetski Qubic Pool](https://qubic.jetskipool.ai/) PPLNS miner.

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
{"miner_profile":{"name":"Qubic-Jetski-PPLNS","coin":"QUBIC","os":"linux","commandline":"./start_qubic.sh --wallet %wallet_address% --rigid %rig_name%%miner_id% --gpu --cpu --cpu-threads $(nproc) --pplns","miner":"custom","miner_version":"latest","custom_url":"https://github.com/Sebdev43/qubjetski-mmpos/releases/download/latest/qubjetski-latest_mmpos.tar.gz","api_port":4444,"platforms":["cpu_intel","cpu_amd","nvidia"]},"pools":[{"url":"pplnsjetski.xyz","port":"443","username":"%wallet_address%.%rig_name%%miner_id%","password":"x","name":"Jetski-Qubic","coin":"QUBIC","ssl":true}]}
```

## Manual Build

```bash
./build.sh
```

## Credits

- Original miner: [jtskxx/Jetski-Qubic-Pool](https://github.com/jtskxx/Jetski-Qubic-Pool)
- Pool: [Jetski Qubic Pool](https://qubic.jetskipool.ai/)
