#!/bin/bash

# Check if there are any arguments passed
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <pattern1> [pattern2] [pattern3] ..."
    exit 1
fi

# Build the find command with dynamic patterns
FIND_CMD="find . -mindepth 1 -maxdepth 1 -type f \\( -false"

for PATTERN in "$@"; do
    FIND_CMD+=" -o -name \"${PATTERN}\""
done

# Complete the find command by closing the parentheses
FIND_CMD+=" \\) | sort"

# Declare REENCODE_FINAL_COMMAND as an empty string
REENCODE_FINAL_COMMAND=""

# Use process substitution to avoid the subshell issue
while IFS= read -r VIDEO_FILE; do
    echo "Processing file $(basename "${VIDEO_FILE}")"
    REENCODE_FINAL_COMMAND+="reencode720p.sh \"$(basename "${VIDEO_FILE}")\" && "
done < <(eval "$FIND_CMD")

# Add the final echo to indicate completion
REENCODE_FINAL_COMMAND+="echo \"C'est fini\""

## Output and execute the final reencode command
echo "Running: $REENCODE_FINAL_COMMAND"
eval "$REENCODE_FINAL_COMMAND"
