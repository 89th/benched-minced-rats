#!/bin/bash

# ANSI escape codes for text formatting
RED='\E[0;31m'
GREEN='\E[0;32m'
YELLOW='\E[0;33m'
BLUE='\E[0;34m'
BOLD='\E[1m'
ITALIC='\E[3m'
RESET='\E[0m'

# Default values for options
interval_opt='1'
output_opt="sensors_$(date +%s).tsv"
command_opt="sensors; "
header_opt=true

display_help() {
    # Define the help menu
    help_menu="
Continuously append data from ${GREEN}${ITALIC}sensors${RESET} to a file in TSV format.

  ${RED}${BOLD}Usage:${RESET}
	$0 [options]
  
  ${RED}${BOLD}Options:${RESET}
	${BLUE}-o [/path/to/output]   ${GREEN}${ITALIC}The filepath to output TSV data.${RESET}
		default: ${RED}\"sensors_<Epoch seconds>.tsv\"${RESET}
		e.g. \"$output_opt\"
	${BLUE}-n [interval]          ${GREEN}${ITALIC}The rate to refresh and request data (in seconds).${RESET}
		default: ${RED}$interval_opt${RESET}
	${BLUE}-c [command]           ${GREEN}${ITALIC}The command to refresh and display while logging sensors. Leave blank for none.${RESET}
		default: ${RED}\"sensors\"${RESET}
	${BLUE}-H [true|false]        ${GREEN}${ITALIC}Write a header to the TSV file.${RESET}
		default: ${RED}$header_opt${RESET}

	${BLUE}-h    ${YELLOW}Display this help menu.${RESET}

  ${RED}${BOLD}Example:${RESET}
    Log without a header to \"my_sensor_log.tsv\" every 0.5 seconds. Displaying ${GREEN}${ITALIC}sensors${RESET} with its output filtered through ${GREEN}${ITALIC}grep${RESET}:
    
        ${GREEN}${ITALIC}$0 -n 0.5 -c \"sensors | grep :\" -H false -o my_sensor_log.tsv${RESET}
  "

    # Print the help menu
    echo -e "$help_menu"
    exit 0
}

numopts=0
while getopts ":h:n:o:c:H:" opt; do
    ((numopts++))
    case $opt in
    n)
        interval_opt="$OPTARG"
        ;;
    o)
        output_opt="$OPTARG"
        ;;
    c)
        command_opt="$OPTARG; "
        ;;
    H)
        if [ "$OPTARG" = "true" ]; then
            header_opt=true
        else
            header_opt=false
        fi
        ;;
    \?)
        echo "Invalid option: -$OPTARG" >&2
        echo "Use \"$0 -h\" for help"
        exit 2
        ;;
    :)
        if [ "$OPTARG" = "h" ]; then
            display_help
            exit 0
        fi
        if [ "$OPTARG" = "c" ]; then
            command_opt=""
            break
        fi
        echo "Option -$OPTARG requires an argument." >&2
        exit 2
        ;;
    esac
done

# Initialize the file with a header line from sensors
if [ "$header_opt" = "true" ]; then
(
    printf "Time (Epoch seconds),"
    sensors | grep : | grep -v Adapter: | sed -r 's/^(.*)\(.*\)(.*)$/\1 \2/g' | sed -e 's/  */ /g' -e 's/ $//g' -e 's/: /:/g' -e 's/°/deg/g' -e 's/%/percent/g' -re 's/(^.*?):[ ]*([^0-9]*[0-9.]+|N\/A)[ ]*([^0-9 ]*)[ ]*$/\1 (\3)/g' | tr '\n' '\t' | sed -e 's/\t$/\n/'
) >>$output_opt
fi

# Main loop
watch -n $interval_opt "$command_opt(printf \"\$(date +%s),\"; sensors | grep : | grep -v Adapter: | sed -r 's/^(.*)\(.*\)(.*)$/\1 \2/g' | sed -e 's/  */ /g' -e 's/ $//g' -e 's/: /:/g' -re 's/^.*?:([^0-9]*[0-9.]+|N\/A)[^0-9]*$/\1/g' | tr '\n' '\t' | sed -e 's/\t$/\n/') >> $output_opt"
