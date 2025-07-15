#!/bin/bash

echo "Stopping and removing all containers with name starting 'node'..."
# This finds all containers (running or stopped) with a name like 'node*' and forces removal.
docker rm -f $(docker ps -a -q --filter "name=node") || true

echo "Removing Docker network..."
docker network rm cosmos-serf-net || true

echo "Cleanup complete."
