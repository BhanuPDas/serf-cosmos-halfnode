# serf-cosmos-halfnode

## Steps to run v3 of the project [For 2 Nodes]:

1. Execute the v3 version of the docker file: ***docker build -t cosmos-serf-dashboard -f Dockerfile.v3 .***
2. Run the docker image for first node(node1): ***docker run --rm -p 5000:5000 --name node1 cosmos-serf-dashboard***
3. Set the environment variables: ***NODE1_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' node1)*** 
4. Run the second node(node2): ***docker run --rm -p 5001:5000 --name node2 -e SERF_SEED_NODE=$NODE1_IP:7946 cosmos-serf-dashboard***

## Steps to run 5 Nodes configuration:

1. Execute the v3 version of the docker file: ***docker build -t cosmos-serf-dashboard -f Dockerfile.v3 .***
2. Execute the script to create 5 Nodes: ***./start_final_app.sh***

## Steps to test and validate the application:

1. Once all nodes are up and running, navigate to ***http://172.22.120.133:5000/*** on browser to get the dashboard and do the transaction.
2. Same transaction details can be verified in docker logs: ***docker logs container_name***
3. Additionally, the data can be verified on packet level.
4. ***Install tshark.***
5. Before doing any transaction, enable tshark to capture packets: ***sudo tshark -i docker0 "udp" -w /tmp/capture23.pcap***
6. Do the transaction
7. After the transaction, validate the details in the packet: ***sudo tshark -r capture23.pcap -V***
