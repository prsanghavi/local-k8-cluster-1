package main

import (
	"fmt"
	"time"

	"go.temporal.io/sdk/workflow"
)

const llmRouterEndpoint = "ob1-nexus-llm-cluster-1-endpoint-1"

var endpointForAIWorker = map[string]string{
	"budytest1": "ob1-uo-temporal-budytest1-gilfoyletest1-1-1",
	"hawthorn":  "ob1-uo-temporal-hawthorn-hope-1-1",
}

type StartChainInput struct {
	ChainID           string
	AIWorker          string
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

// StartChainWorkflow starts in Comms and invokes one AI worker. That worker
// calls LLM Router, receives its result, and returns the final result to Comms.
func StartChainWorkflow(ctx workflow.Context, input StartChainInput) (ChainResult, error) {
	if input.ChainID == "" {
		return ChainResult{}, fmt.Errorf("ChainID is required")
	}
	sizes, err := validatedPayloadSizes(input.PayloadSizesBytes)
	if err != nil {
		return ChainResult{}, err
	}
	endpoint, ok := endpointForAIWorker[input.AIWorker]
	if !ok {
		return ChainResult{}, fmt.Errorf("AIWorker must be budytest1 or hawthorn")
	}
	payload, err := generatePayload(ctx, input.ChainID, 0, sizes[0])
	if err != nil {
		return ChainResult{}, err
	}
	return callEndpoint(ctx, endpoint, RelayInput{ChainID: input.ChainID, Hop: 0, Payload: payload, PayloadSizesBytes: sizes})
}

// RelayWorkflow runs in an AI worker or LLM Router. AI workers receive hop 0
// and call LLM; LLM receives hop 1 and returns. Nexus response envelopes carry
// the result back through the same AI worker to Comms.
func RelayWorkflow(ctx workflow.Context, input RelayInput) (ChainResult, error) {
	activityCtx := workflow.WithActivityOptions(ctx, workflow.ActivityOptions{StartToCloseTimeout: time.Minute})
	if err := workflow.ExecuteActivity(activityCtx, PrintPayloadActivity, input).Get(activityCtx, nil); err != nil {
		return ChainResult{}, err
	}

	if input.Hop == 1 {
		return ChainResult{ChainID: input.ChainID, CompletedHop: input.Hop, PayloadSHA256: payloadSHA256(input.Payload)}, nil
	}

	nextHop := input.Hop + 1
	payload, err := generatePayload(ctx, input.ChainID, nextHop, input.PayloadSizesBytes[nextHop])
	if err != nil {
		return ChainResult{}, err
	}
	next := RelayInput{ChainID: input.ChainID, Hop: nextHop, Payload: payload, PayloadSizesBytes: input.PayloadSizesBytes}
	return callEndpoint(ctx, llmRouterEndpoint, next)
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
		return []int{320 * 1024, 320 * 1024}, nil
	}
	if len(sizes) != 2 {
		return nil, fmt.Errorf("PayloadSizesBytes must contain exactly 2 values")
	}
	for _, size := range sizes {
		if size <= 0 {
			return nil, fmt.Errorf("PayloadSizesBytes values must be positive")
		}
	}
	return sizes, nil
}

func callEndpoint(ctx workflow.Context, endpoint string, input RelayInput) (ChainResult, error) {
	nexusClient := workflow.NewNexusClient(endpoint, nexusServiceName)
	future := nexusClient.ExecuteOperation(ctx, nexusOperation, input, workflow.NexusOperationOptions{ScheduleToCloseTimeout: 5 * time.Minute})
	var result ChainResult
	return result, future.Get(ctx, &result)
}
