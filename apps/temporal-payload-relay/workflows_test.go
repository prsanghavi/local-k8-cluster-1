package main

import "testing"

func TestLargePayloadExceedsExternalStorageThreshold(t *testing.T) {
	payload, err := GenerateLargePayloadActivity(nil, GenerateInput{ChainID: "test-chain", Hop: 0})
	if err != nil {
		t.Fatal(err)
	}
	if len(payload) <= 256*1024 {
		t.Fatalf("payload is %d bytes; it must exceed the 256 KiB offload threshold", len(payload))
	}
}

func TestNexusRouteHasFourEndpoints(t *testing.T) {
	if len(endpointForHop) != 4 {
		t.Fatalf("got %d endpoints, want 4", len(endpointForHop))
	}
}
