#!/bin/bash

# Define workspace
WORKDIR="/root/agsbx"
mkdir -p "$WORKDIR"

# Ensure permissions
chmod +x /app/main.sh /app/modules/*.sh

# Run the Main Orchestrator
# This will configure and start services in background (nohup mode)
echo "Starting Argosbx Orchestrator..."
/app/main.sh install

# Keep container alive by tailing logs
# We wait a bit for logs to be created
sleep 5

echo "Services started. Tailing logs..."
tail -f "$WORKDIR"/*.log 2>/dev/null || tail -f /dev/null
