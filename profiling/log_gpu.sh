#!/bin/bash

# Forgive me for what I must yabba dabba do

starttime=$(date +%s)

printf "timestamp,timerfc,$(rocm-smi --showuse --showmemuse --csv | head -n 1 | sed 's/%//g')" > vmstat_gpu_${starttime}.log

watch -n 1 "printf \"\$(date +%s),\$(date --rfc-3339='seconds'),\$(rocm-smi --showuse --showmemuse --csv | head -n 2 | tail -n 1)\n\" >> vmstat_gpu_${starttime}.log"