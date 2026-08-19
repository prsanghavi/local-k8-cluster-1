package main

import "testing"

func TestLargePayloadExceedsExternalStorageThreshold(t *testing.T) {
	payload, err := GenerateLargePayloadActivity(nil, GenerateInput{ChainID: "test-chain", Hop: 0, SizeBytes: externalStorageThresholdBytes + 1})
	if err != nil {
		t.Fatal(err)
	}
	if len(payload) <= 256*1024 {
		t.Fatalf("payload is %d bytes; it must exceed the 256 KiB offload threshold", len(payload))
	}
}

func TestPayloadSizesDefaultAndCustom(t *testing.T) {
	defaults, err := validatedPayloadSizes(nil)
	if err != nil || len(defaults) != 2 {
		t.Fatalf("defaults: %v, %v", defaults, err)
	}
	if _, err := validatedPayloadSizes([]int{1, 2, 3}); err == nil {
		t.Fatal("expected size count validation error")
	}
}

func TestNexusRouteHasAIWorkerEndpoints(t *testing.T) {
	if len(endpointForAIWorker) != 2 {
		t.Fatalf("got %d AI worker endpoints, want 2", len(endpointForAIWorker))
	}
	if endpointForAIWorker["budytest1"] == "" || endpointForAIWorker["hawthorn"] == "" {
		t.Fatal("AI worker endpoint mapping is incomplete")
	}
}
