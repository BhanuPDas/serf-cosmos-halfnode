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
