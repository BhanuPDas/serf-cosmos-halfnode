# serf-cosmos-halfnode

## Steps to run v3 of the project:

1. Execute the v3 version of the docker file: docker build -t cosmos-serf-dashboard -f Dockerfile.v3 . 
2. Run the docker image for first node(node1): docker run --rm -p 5000:5000 --name node1 cosmos-serf-dashboard
3. Set the environment variables: NODE1_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' node1) 
4. Run the second node(node2): docker run --rm -p 5001:5000 --name node2 -e SERF_SEED_NODE=$NODE1_IP:7946 cosmos-serf-dashboard