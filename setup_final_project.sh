#!/bin/bash

echo "🚀 Performing final project cleanup and creating consolidated Raft application files..."

# --- Step 1: Forcefully delete all old and conflicting Go files ---
echo "Cleaning up old project files..."
rm -f state.go contracts.go mempool.go serf_manager.go main_simple_consensus.go

# --- Step 2: Create the new, consolidated fsm.go ---
# This file now contains the StateMachine, Transaction, and FSM logic.
echo "Creating final fsm.go..."
cat > fsm.go << 'EOF'
package main

import (
	"encoding/json"
	"fmt"
	"hash/fnv"
	"io"
	"log"
	"sort"
	"sync"

	"github.com/hashicorp/raft"
)

type Transaction struct {
	Contract string                 `json:"contract"`
	From     string                 `json:"from"`
	To       string                 `json:"to,omitempty"`
	Amount   int                    `json:"amount,omitempty"`
	Context  map[string]interface{} `json:"-"`
}

type StateMachine struct {
	mu         sync.RWMutex
	Accounts   map[string]int `json:"accounts"`
	ChosenNode string         `json:"chosen_node"`
}

func NewStateMachine() *StateMachine {
	return &StateMachine{
		Accounts: map[string]int{
			"alice": 1000, "bob": 1000, "charlie": 1000,
		},
	}
}

type FSM struct{ sm *StateMachine }

func (f *FSM) Apply(logEntry *raft.Log) interface{} {
	var tx Transaction
	if err := json.Unmarshal(logEntry.Data, &tx); err != nil {
		panic(fmt.Sprintf("failed to unmarshal log data: %s", err))
	}
	f.sm.mu.Lock()
	defer f.sm.mu.Unlock()

	log.Printf("[FSM] Executing contract: %s", tx.Contract)

	switch tx.Contract {
	case "transfer":
		if f.sm.Accounts[tx.From] < tx.Amount {
			return fmt.Errorf("insufficient funds")
		}
		f.sm.Accounts[tx.From] -= tx.Amount
		f.sm.Accounts[tx.To] += tx.Amount
	case "choose_node":
		members, ok := tx.Context["members"].([]string)
		if !ok || len(members) == 0 {
			return fmt.Errorf("no active nodes to choose from")
		}
		sort.Strings(members)
		hasher := fnv.New32a()
		blockTime, _ := tx.Context["block_time"].(int64)
		hasher.Write([]byte(fmt.Sprintf("%v", blockTime)))
		index := int(hasher.Sum32()) % len(members)
		f.sm.ChosenNode = members[index]
	default:
		return fmt.Errorf("unknown contract: %s", tx.Contract)
	}
	return nil
}

func (f *FSM) Snapshot() (raft.FSMSnapshot, error) {
	f.sm.mu.RLock()
	defer f.sm.mu.RUnlock()
	data, err := json.Marshal(f.sm)
	if err != nil { return nil, err }
	return &fsmSnapshot{data: data}, nil
}

func (f *FSM) Restore(rc io.ReadCloser) error {
	data, err := io.ReadAll(rc)
	if err != nil { return err }
	var sm StateMachine
	if err := json.Unmarshal(data, &sm); err != nil { return err }
	f.sm = &sm
	return nil
}

type fsmSnapshot struct{ data []byte }
func (s *fsmSnapshot) Persist(sink raft.SnapshotSink) error {
	err := func() error {
		if _, err := sink.Write(s.data); err != nil { return err }
		return sink.Close()
	}()
	if err != nil { sink.Cancel() }
	return err
}
func (s *fsmSnapshot) Release() {}
EOF

# --- Step 3: Create the new, consolidated consensus.go ---
echo "Creating final consensus.go..."
cat > consensus.go << 'EOF'
package main

import (
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"time"

	"github.com/hashicorp/raft"
	"github.com/hashicorp/raft-boltdb/v2"
)

type ConsensusNode struct {
	Raft *raft.Raft
}

func NewConsensusNode(nodeID, raftAddr, dataDir string, fsm raft.FSM) (*ConsensusNode, error) {
	config := raft.DefaultConfig()
	config.LocalID = raft.ServerID(nodeID)
	addr, err := net.ResolveTCPAddr("tcp", raftAddr)
	if err != nil { return nil, err }
	transport, err := raft.NewTCPTransport(raftAddr, addr, 3, 10*time.Second, os.Stderr)
	if err != nil { return nil, err }
	snapshots, err := raft.NewFileSnapshotStore(dataDir, 2, os.Stderr)
	if err != nil { return nil, err }
	logStore, err := raftboltdb.New(raftboltdb.Options{Path: filepath.Join(dataDir, "raft.db")})
	if err != nil { return nil, err }
	raftNode, err := raft.NewRaft(config, fsm, logStore, logStore, snapshots, transport)
	if err != nil { return nil, err }
	bootstrapConfig := raft.Configuration{
		Servers: []raft.Server{{ID: config.LocalID, Address: transport.LocalAddr()}},
	}
	raftNode.BootstrapCluster(bootstrapConfig)
	return &ConsensusNode{Raft: raftNode}, nil
}

func (cn *ConsensusNode) ProposeTransaction(tx Transaction) error {
	data, err := json.Marshal(tx)
	if err != nil { return err }
	future := cn.Raft.Apply(data, 500*time.Millisecond)
	return future.Error()
}
EOF

# --- Step 4: Create the new, consolidated main.go ---
echo "Creating final main.go..."
cat > main.go << 'EOF'
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
		defer f.sm.mu.RUnlock()
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
EOF

echo ""
echo "✅ Project cleanup and consolidation complete!"
