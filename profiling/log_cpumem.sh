#!/bin/bash

starttime=$(date +%s)
vmstat 5 -twn >> vmstat_cpumem_${starttime}.log