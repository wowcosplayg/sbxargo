#!/bin/bash

# Wrapper to run the main installation script
# Ensures execution from the correct directory

BASE_DIR="$(dirname "$(readlink -f "$0")")"
cd "$BASE_DIR"

if [ -f "./main.sh" ]; then
    bash ./main.sh "$@"
else
    echo "Error: main.sh not found!"
    exit 1
fi
