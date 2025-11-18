#!/bin/bash

starttime=$(date +%s)
iostat -xzdty 5 >> system_io_${starttime}.log
