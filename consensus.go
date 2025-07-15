package main

import (
	"encoding/json"
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
