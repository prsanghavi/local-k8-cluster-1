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
	ChainID           string
	PayloadSizesBytes []int
}

type RelayInput struct {
	ChainID           string
	Hop               int
	Payload           string
	PayloadSizesBytes []int
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
	sizes, err := validatedPayloadSizes(input.PayloadSizesBytes)
	if err != nil {
		return ChainResult{}, err
	}
	payload, err := generatePayload(ctx, input.ChainID, 0, sizes[0])
	if err != nil {
		return ChainResult{}, err
	}
	return callNext(ctx, RelayInput{ChainID: input.ChainID, Hop: 0, Payload: payload, PayloadSizesBytes: sizes})
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
		return ChainResult{ChainID: input.ChainID, CompletedHop: input.Hop, PayloadSHA256: payloadSHA256(input.Payload)}, nil
	}

	nextHop := input.Hop + 1
	payload, err := generatePayload(ctx, input.ChainID, nextHop, input.PayloadSizesBytes[nextHop])
	if err != nil {
		return ChainResult{}, err
	}
	next := RelayInput{ChainID: input.ChainID, Hop: nextHop, Payload: payload, PayloadSizesBytes: input.PayloadSizesBytes}
	return callNext(ctx, next)
}

// generatePayload creates the message in an activity so the normal Temporal
// external-storage path is exercised before the payload is sent directly via
// Nexus. The shared module's converter hydrates an SDK storage reference at the
// Nexus decoding boundary when the payload exceeds the configured threshold.
func generatePayload(ctx workflow.Context, chainID string, hop, sizeBytes int) (string, error) {
	activityCtx := workflow.WithActivityOptions(ctx, workflow.ActivityOptions{StartToCloseTimeout: time.Minute})
	var payload string
	if err := workflow.ExecuteActivity(activityCtx, GenerateLargePayloadActivity, GenerateInput{ChainID: chainID, Hop: hop, SizeBytes: sizeBytes}).Get(activityCtx, &payload); err != nil {
		return "", err
	}
	return payload, nil
}

func validatedPayloadSizes(sizes []int) ([]int, error) {
	if len(sizes) == 0 {
		return []int{320 * 1024, 320 * 1024, 320 * 1024, 320 * 1024}, nil
	}
	if len(sizes) != len(endpointForHop) {
		return nil, fmt.Errorf("PayloadSizesBytes must contain exactly %d values", len(endpointForHop))
	}
	for _, size := range sizes {
		if size <= 0 {
			return nil, fmt.Errorf("PayloadSizesBytes values must be positive")
		}
	}
	return sizes, nil
}

func callNext(ctx workflow.Context, input RelayInput) (ChainResult, error) {
	endpoint := endpointForHop[input.Hop]
	nexusClient := workflow.NewNexusClient(endpoint, nexusServiceName)
	future := nexusClient.ExecuteOperation(ctx, nexusOperation, input, workflow.NexusOperationOptions{ScheduleToCloseTimeout: 5 * time.Minute})
	var result ChainResult
	return result, future.Get(ctx, &result)
}
