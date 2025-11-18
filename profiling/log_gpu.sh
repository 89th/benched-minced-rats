#!/bin/bash

starttime=$(date +%s)

printf "timestamp,timerfc,$(rocm-smi --showuse --showmemuse --csv | head -n 1 | sed 's/%//g')" > system_gpu_${starttime}.log

watch -n 1 "printf \"\$(date +%s),\$(date --rfc-3339='seconds'),\$(rocm-smi --showuse --showmemuse --csv | head -n 2 | tail -n 1)\n\" >> system_gpu_${starttime}.log"
