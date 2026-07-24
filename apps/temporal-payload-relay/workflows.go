package main

import (
	"fmt"
	"time"

	"go.temporal.io/sdk/workflow"
)

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
	Payload PayloadReference
}

type ChainResult struct {
	ChainID       string
	CompletedHop  int
	PayloadSHA256 string
}

// StartChainWorkflow starts in the Comms namespace and invokes the LLM worker.
func StartChainWorkflow(ctx workflow.Context, input StartChainInput) (ChainResult, error) {
	if input.ChainID == "" {
		return ChainResult{}, fmt.Errorf("ChainID is required")
	}
	payload, err := createAndPersistPayload(ctx, input.ChainID, 0)
	if err != nil {
		return ChainResult{}, err
	}
	return callNext(ctx, RelayInput{ChainID: input.ChainID, Hop: 0, Payload: payload})
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
		return ChainResult{ChainID: input.ChainID, CompletedHop: input.Hop, PayloadSHA256: input.Payload.SHA256}, nil
	}

	payload, err := createAndPersistPayload(ctx, input.ChainID, input.Hop+1)
	if err != nil {
		return ChainResult{}, err
	}
	next := RelayInput{ChainID: input.ChainID, Hop: input.Hop + 1, Payload: payload}
	return callNext(ctx, next)
}

// createAndPersistPayload deliberately crosses two activity boundaries with the
// 320 KiB string. The configured Temporal external storage driver offloads that
// activity result/input, while PersistPayloadActivity verifies the final MinIO
// object that is handed off through Nexus.
func createAndPersistPayload(ctx workflow.Context, chainID string, hop int) (PayloadReference, error) {
	activityCtx := workflow.WithActivityOptions(ctx, workflow.ActivityOptions{StartToCloseTimeout: time.Minute})
	var payload string
	if err := workflow.ExecuteActivity(activityCtx, GenerateLargePayloadActivity, GenerateInput{ChainID: chainID, Hop: hop}).Get(activityCtx, &payload); err != nil {
		return PayloadReference{}, err
	}
	var reference PayloadReference
	err := workflow.ExecuteActivity(activityCtx, PersistPayloadActivity, PersistInput{ChainID: chainID, Hop: hop, Payload: payload}).Get(activityCtx, &reference)
	return reference, err
}

func callNext(ctx workflow.Context, input RelayInput) (ChainResult, error) {
	endpoint := endpointForHop[input.Hop]
	nexusClient := workflow.NewNexusClient(endpoint, nexusServiceName)
	future := nexusClient.ExecuteOperation(ctx, nexusOperation, input, workflow.NexusOperationOptions{ScheduleToCloseTimeout: 5 * time.Minute})
	var result ChainResult
	return result, future.Get(ctx, &result)
}
