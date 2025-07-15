#!/bin/bash

# --- Configuration ---

NUM_NODES=${1:-5}

TERMINAL_CMD="gnome-terminal --"

# --- Validation ---
if [ "$NUM_NODES" -lt 1 ]; then
    echo "Error: Number of nodes must be at least 1."
    exit 1
fi

echo "--- Starting a ${NUM_NODES}-node P2P cluster ---"

# --- Cleanup ---
echo "Cleaning up old containers..."
for i in $(seq 1 $NUM_NODES); do
    docker stop "node$i" > /dev/null 2>&1
done
docker container prune -f > /dev/null

# --- Start Seed Node ---
echo "Starting node1 (seed node)..."
docker run -d --rm -p 5000:5000 --name node1 cosmos-serf-dashboard

# Give the container a moment to start and get an IP address
sleep 2

NODE1_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' node1)
if [ -z "$NODE1_IP" ]; then
    echo "Error: Could not get the IP address of node1. Aborting."
    exit 1
fi
echo "Seed node IP is: $NODE1_IP"

# --- Start Follower Nodes ---
for i in $(seq 2 $NUM_NODES); do
    HOST_PORT=$((4999 + i))
    echo "Starting node${i} and connecting to cluster..."
    docker run -d --rm -p "${HOST_PORT}:5000" --name "node${i}" -e "SERF_SEED_NODE=${NODE1_IP}:7946" cosmos-serf-dashboard
done

echo ""
echo "Cluster started successfully"
echo ""


# The 'exec bash' at the end keeps the terminal open after the log command finishes.
echo "Opening new terminal windows for logs..."
for i in $(seq 1 $NUM_NODES); do
    $TERMINAL_CMD sh -c "echo '--- LOGS FOR NODE ${i} ---'; docker logs -f node${i}; exec bash" &
done

echo ""
echo "Dashboard URLs:"
for i in $(seq 1 $NUM_NODES); do
    HOST_PORT=$((4999 + i))
    echo "  - Node ${i}: http://<our vm-ip>:${HOST_PORT}"
done
echo ""
echo "To stop the entire cluster, run: docker stop \$(docker ps -q --filter 'name=node')"
