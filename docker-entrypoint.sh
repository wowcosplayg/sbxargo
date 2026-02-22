#!/bin/bash

# Define workspace
WORKDIR="/root/agsbx"
mkdir -p "$WORKDIR"

# Ensure permissions
chmod +x /app/main.sh /app/modules/*.sh

# Run the Main Orchestrator
# This will configure and start services in background (nohup mode)
if [ -f "$WORKDIR/xr.json" ] || [ -f "$WORKDIR/sb.json" ]; then
    echo "Existing configuration detected. Performing fast start..."
    /app/main.sh service_start
else
    echo "Starting Argosbx Orchestrator Initial Installation..."
    /app/main.sh install
fi

# Keep container alive by tailing logs
# We wait a bit for logs to be created
sleep 5

echo "Services started. Tailing logs..."
tail -f "$WORKDIR"/*.log 2>/dev/null || tail -f /dev/null
