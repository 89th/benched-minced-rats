#!/bin/bash

starttime=$(date +%s)
vmstat 5 -dtwn >> vmstat_disk_${starttime}.log