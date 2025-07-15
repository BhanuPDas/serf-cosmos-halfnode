#!/bin/bash

# Find all running containers with 'node' in their name
NODES=$(docker ps --filter "name=node" --format "{{.Names}}")

if [ -z "$NODES" ]; then
  echo "No running nodes found."
  exit 1
fi

# Loop through each node and get its view of the cluster
for node in $NODES; do
  echo "========================================="
  echo "Serf members as seen by: $node"
  echo "========================================="
  docker exec "$node" serf members
  echo ""
done
