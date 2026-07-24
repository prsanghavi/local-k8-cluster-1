package main

import (
	"crypto/sha256"
	"fmt"
	"strings"
	"time"

	"go.temporal.io/sdk/workflow"
)

const payloadBytes = 320 * 1024

var endpointForHop = []string{
	"ob1-nexus-llm-cluster-1-endpoint-1",
	"ob1-uo-temporal-budytest1-gilfoyletest1-1-1",
	"ob1-uo-temporal-hawthorn-hope-1-1",
	"ob1-nexus-comms-cluster-1-endpoint-1",
}

type StartChainInput struct {
	ChainID string
}

type RelayInput struct {
	ChainID string
	Hop     int
	Payload string
}

type ChainResult struct {
	ChainID     string
	CompletedHop int
	PayloadSHA256 string
}

// StartChainWorkflow starts in the Comms namespace and invokes the LLM worker.
func StartChainWorkflow(ctx workflow.Context, input StartChainInput) (ChainResult, error) {
	if input.ChainID == "" {
		return ChainResult{}, fmt.Errorf("ChainID is required")
	}
	return callNext(ctx, RelayInput{ChainID: input.ChainID, Hop: 0, Payload: largePayload(input.ChainID, 0)})
}

// RelayWorkflow runs in the target namespace for a Nexus operation. Each hop
// prints its received payload in an activity, then creates the next payload.
func RelayWorkflow(ctx workflow.Context, input RelayInput) (ChainResult, error) {
	activityCtx := workflow.WithActivityOptions(ctx, workflow.ActivityOptions{StartToCloseTimeout: time.Minute})
	if err := workflow.ExecuteActivity(activityCtx, PrintPayloadActivity, input).Get(activityCtx, nil); err != nil {
		return ChainResult{}, err
	}

	// Hop 3 reaches Comms through the fourth endpoint and completes the cycle.
	if input.Hop == len(endpointForHop)-1 {
		sum := sha256.Sum256([]byte(input.Payload))
		return ChainResult{ChainID: input.ChainID, CompletedHop: input.Hop, PayloadSHA256: fmt.Sprintf("%x", sum[:])}, nil
	}

	next := RelayInput{ChainID: input.ChainID, Hop: input.Hop + 1, Payload: largePayload(input.ChainID, input.Hop+1)}
	return callNext(ctx, next)
}

func callNext(ctx workflow.Context, input RelayInput) (ChainResult, error) {
	endpoint := endpointForHop[input.Hop]
	nexusClient := workflow.NewNexusClient(endpoint, nexusServiceName)
	future := nexusClient.ExecuteOperation(ctx, nexusOperation, input, workflow.NexusOperationOptions{ScheduleToCloseTimeout: 5 * time.Minute})
	var result ChainResult
	return result, future.Get(ctx, &result)
}

func largePayload(chainID string, hop int) string {
	prefix := fmt.Sprintf("chain=%s hop=%d ", chainID, hop)
	return prefix + strings.Repeat("payload-data-", (payloadBytes/len("payload-data-"))+1)
}
