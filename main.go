package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/hashicorp/raft"
	"github.com/hashicorp/serf/serf"
)

func main() {
	nodeID := os.Getenv("NODE_ID")
	if nodeID == "" {
		hostname, _ := os.Hostname()
		nodeID = hostname
	}
	serfAddr := "0.0.0.0:7946"
	raftAddr := "0.0.0.0:12000"
	httpAddr := "0.0.0.0:8080"
	dataDir := fmt.Sprintf("./data/%s", nodeID)
	os.MkdirAll(dataDir, os.ModePerm)

	log.Printf("[MAIN] Starting node %s...", nodeID)

	fsm := &FSM{sm: NewStateMachine()}
	consensusNode, err := NewConsensusNode(nodeID, raftAddr, dataDir, fsm)
	if err != nil {
		log.Fatalf("[FATAL] Failed to create consensus node: %s", err)
	}

	serfAgent, err := NewDiscoveryService(serfAddr, raftAddr, nodeID, consensusNode)
	if err != nil {
		log.Fatalf("[FATAL] Failed to create serf agent: %s", err)
	}

	if seedNode := os.Getenv("SERF_SEED_NODE"); seedNode != "" {
		log.Printf("[MAIN] Attempting to join cluster via seed node: %s", seedNode)
		_, err := serfAgent.Join([]string{seedNode}, true)
		if err != nil {
			log.Printf("[WARN] Could not join cluster via seed node: %v", err)
		}
	}

	go startAPIServer(httpAddr, consensusNode, fsm)

	log.Println("[MAIN] Node started successfully.")
	select {}
}

func startAPIServer(httpAddr string, consensusNode *ConsensusNode, fsm *FSM) {
	http.HandleFunc("/propose", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Only POST method is allowed", http.StatusMethodNotAllowed)
			return
		}
		var tx Transaction
		if err := json.NewDecoder(r.Body).Decode(&tx); err != nil {
			http.Error(w, "Invalid transaction format", http.StatusBadRequest)
			return
		}

		if tx.Contract == "choose_node" {
			tx.Context = make(map[string]interface{})
			configFuture := consensusNode.Raft.GetConfiguration()
			if err := configFuture.Error(); err != nil {
				log.Printf("[ERROR] Failed to get raft configuration: %v", err)
				http.Error(w, "Failed to get cluster configuration", 500)
				return
			}
			members := configFuture.Configuration().Servers
			var aliveNodes []string
			for _, srv := range members {
				aliveNodes = append(aliveNodes, string(srv.ID))
			}
			tx.Context["members"] = aliveNodes
			tx.Context["block_time"] = time.Now().Unix()
		}

		if err := consensusNode.ProposeTransaction(tx); err != nil {
			http.Error(w, fmt.Sprintf("Failed to propose transaction: %s", err), http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, "Transaction proposed successfully.")
	})

	http.HandleFunc("/status", func(w http.ResponseWriter, r *http.Request) {
		fsm.sm.mu.RLock()
		defer fsm.sm.mu.RUnlock()
		status := map[string]interface{}{
			"leader": string(consensusNode.Raft.Leader()),
			"state":  fsm.sm,
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(status)
	})

	log.Printf("[API] HTTP server listening on %s", httpAddr)
	if err := http.ListenAndServe(httpAddr, nil); err != nil {
		log.Fatalf("[FATAL] HTTP server failed: %v", err)
	}
}

func NewDiscoveryService(serfAddr, raftAddr, nodeID string, consensusNode *ConsensusNode) (*serf.Serf, error) {
	config := serf.DefaultConfig()
	config.Init()
	config.NodeName = nodeID
	eventCh := make(chan serf.Event, 256)
	config.EventCh = eventCh
	config.Tags = map[string]string{"raft_addr": raftAddr}
	serfAgent, err := serf.Create(config)
	if err != nil { return nil, err }

	go func() {
		for e := range eventCh {
			if e.EventType() == serf.EventMemberJoin {
				for _, member := range e.(serf.MemberEvent).Members {
					if member.Name == nodeID { continue }
					raftAddr, ok := member.Tags["raft_addr"]
					if !ok { continue }
					log.Printf("[DISCOVERY] New peer %s discovered at %s", member.Name, raftAddr)
					future := consensusNode.Raft.AddVoter(raft.ServerID(member.Name), raft.ServerAddress(raftAddr), 0, 0)
					if err := future.Error(); err != nil {
						log.Printf("[ERROR] Failed to add peer %s to Raft cluster: %s", member.Name, err)
					}
				}
			}
		}
	}()

	return serfAgent, nil
}
