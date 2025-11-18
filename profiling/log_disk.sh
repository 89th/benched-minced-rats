#!/bin/bash

starttime=$(date +%s)
vmstat 5 -dtwn >> system_disk_${starttime}.log

