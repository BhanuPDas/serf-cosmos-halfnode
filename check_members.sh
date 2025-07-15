#!/bin/bash
echo "Serf members as seen from node1:"
docker exec node1 serf members
