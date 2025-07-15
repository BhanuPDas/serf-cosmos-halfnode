#!/bin/bash

# This is an automation script to create the final deployment files.
# Save this script as 'setup_raft_deployment.sh', make it executable, and run it.

echo "🚀 Creating final deployment files for the Raft-powered application..."

# --- Step 1: Create the Final Dockerfile ---
# This Dockerfile will build our complete application.
echo "📄 Creating Dockerfile.raft..."
cat > Dockerfile.raft << 'EOF'
# Use a single stage that has Go for building our application.
FROM golang:1.24-alpine

# Install git, as it's needed for 'go get' to fetch some dependencies.
RUN apk --no-cache add git

# Set up the application directory
WORKDIR /app

# Copy the module files and download dependencies first for better caching
COPY go.mod go.sum ./
RUN go get
RUN go mod download

# Copy all our Go source code into the container
COPY . .

# Build the Go application
RUN go build -o /go-app .

# Expose the ports for Serf, Raft, and the HTTP API
EXPOSE 7946
EXPOSE 12000
EXPOSE 8080

# The command to run when the container starts
CMD ["/go-app"]
EOF

# --- Step 2: Create the Final Cluster Startup Script ---
# This script will launch a multi-node cluster.
echo "🚀 Creating start_raft_cluster.sh..."
cat > start_raft_cluster.sh << 'EOF'
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
EOF

echo ""
echo "✅ Deployment files created successfully!"
echo "Next steps:"
echo "1. Build the new image: docker build -t cosmos-raft-app -f Dockerfile.raft ."
echo "2. Make the startup script executable: chmod +x start_raft_cluster.sh"
echo "3. Run the cluster: ./start_raft_cluster.sh"
