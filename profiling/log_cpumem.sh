#!/bin/bash

starttime=$(date +%s)
vmstat 5 -twn >> system_cpumem_${starttime}.log

