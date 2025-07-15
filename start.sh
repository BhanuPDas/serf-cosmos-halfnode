#!/bin/sh

# Start the Go P2P service in the background
echo "[start.sh] Starting Go P2P service in the background..."
./go-p2p-service &

# Give it a moment to initialize
sleep 2


echo "[start.sh] Waiting for Go service to become available..."
while ! curl -s http://localhost:8080/status > /dev/null; do
    echo "[start.sh] Go service not ready yet, waiting 1 second..."
    sleep 1
done

echo "[start.sh]  Go service is online!"
echo "[start.sh] Starting Flask web dashboard..."

exec gunicorn --bind 0.0.0.0:5000 --workers 2 webapp.app:app
