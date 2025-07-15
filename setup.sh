#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
NODE_IMAGE="cosmos-serf-node"
DASHBOARD_IMAGE="cosmos-serf-dashboard"
NETWORK_NAME="cosmos-serf-net"
NUM_NODES=5 # How many nodes to create

# --- Build Phase ---
echo "Building Docker images..."
docker build -t $NODE_IMAGE .
# You might have used a specific Dockerfile for the dashboard, like -f Dockerfile.v3
# If so, use the line below instead.
# docker build -t $DASHBOARD_IMAGE -f Dockerfile.v3 .


# --- Network Phase ---
# Create a dedicated network for nodes to find each other by name
if [ ! "$(docker network ls | grep $NETWORK_NAME)" ]; then
  echo "Creating Docker network: $NETWORK_NAME"
  docker network create $NETWORK_NAME
fi

# --- Teardown old containers ---
echo "Stopping and removing any old containers..."
docker rm -f $(docker ps -a -q --filter "name=node") || true


# --- Launch Phase ---
echo "Launching Node 1 (Seed Node)..."
# Using --network-alias allows other containers to find it by the name 'node1'
docker run -d --rm --name node1 --network $NETWORK_NAME --network-alias node1 $NODE_IMAGE

# Get the IP of the seed node
# Using the alias is better, but SERF_SEED_NODE often needs an IP.
# We will use the alias 'node1' as the seed host directly.
SEED_HOST="node1:7946"
echo "Seed node is available at $SEED_HOST"


# Launch subsequent nodes
for i in $(seq 2 $NUM_NODES); do
  echo "Launching Node $i..."
  docker run -d --rm --name "node$i" --network $NETWORK_NAME \
    -e SERF_SEED_NODE=$SEED_HOST \
    $NODE_IMAGE
done

echo "Network setup complete!"
docker ps
