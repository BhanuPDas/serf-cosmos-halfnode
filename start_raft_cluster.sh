#!/bin/bash

NUM_NODES=${1:-3}
echo "--- Starting a ${NUM_NODES}-node Raft cluster ---"

# 1. Cleanup old containers
echo "Cleaning up old containers..."
for i in $(seq 1 $NUM_NODES); do
    docker stop "raft-node$i" > /dev/null 2>&1
done
docker container prune -f > /dev/null

# 2. Start the first node (seed node)
echo "Starting raft-node1 (seed node)..."
docker run -d --rm \
    -p 8080:8080 \
    -p 7946:7946 \
    -p 12000:12000 \
    --name raft-node1 \
    -e "NODE_ID=node1" \
    cosmos-raft-app

sleep 2

# 3. Get the IP address of the seed node for others to join
NODE1_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' raft-node1)
if [ -z "$NODE1_IP" ]; then
    echo "Error: Could not get the IP address of raft-node1. Aborting."
    exit 1
fi
echo "Seed node discovered at: $NODE1_IP"

# 4. Start the rest of the nodes
for i in $(seq 2 $NUM_NODES); do
    HTTP_PORT=$((8079 + i))
    RAFT_PORT=$((11999 + i))
    SERF_PORT=$((7945 + i))
    
    echo "Starting raft-node${i}..."
    docker run -d --rm \
        -p "${HTTP_PORT}:8080" \
        -p "${RAFT_PORT}:12000" \
        -p "${SERF_PORT}:7946" \
        --name "raft-node${i}" \
        -e "NODE_ID=node${i}" \
        -e "SERF_SEED_NODE=${NODE1_IP}:7946" \
        cosmos-raft-app
done

echo ""
echo "✅ Cluster started successfully!"
echo "To see logs for a node, run: docker logs -f raft-node<number>"
echo "To stop the cluster, run: docker stop \$(docker ps -q --filter 'name=raft-node')"
