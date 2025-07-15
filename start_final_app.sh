#!/bin/bash
NUM_NODES=${1:-5}
echo "--- Starting a ${NUM_NODES}-node blockchain cluster ---"
echo "Cleaning up old containers..."
for i in $(seq 1 $NUM_NODES); do
    docker stop "node$i" > /dev/null 2>&1
done
docker container prune -f > /dev/null
echo "Starting node1 (seed node)..."
docker run -d --rm -p 5000:5000 --name node1 cosmos-serf-dashboard
sleep 2
NODE1_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' node1)
if [ -z "$NODE1_IP" ]; then
    echo "Error: Could not get the IP address of node1. Aborting."
    exit 1
fi
for i in $(seq 2 $NUM_NODES); do
    HOST_PORT=$((4999 + i))
    echo "Starting node${i}..."
    docker run -d --rm -p "${HOST_PORT}:5000" --name "node${i}" -e "SERF_SEED_NODE=${NODE1_IP}:7946" cosmos-serf-dashboard
done
echo ""
echo "Cluster started successfully!"
echo "Dashboard URLs:"
for i in $(seq 1 $NUM_NODES); do
    HOST_PORT=$((4999 + i))
    echo "  - Node ${i}: http://<-vm-ip>:${HOST_PORT}"
done
echo ""
echo "To stop the entire cluster, run: docker stop \$(docker ps -q --filter 'name=node')"
