package main

import (
	"context"
	"crypto/sha256"
	"log"
)

// PrintPayloadActivity logs the full payload to prove that the receiver was
// able to dereference the MinIO-backed payload before forwarding the chain.
func PrintPayloadActivity(_ context.Context, input RelayInput) error {
	sum := sha256.Sum256([]byte(input.Payload))
	log.Printf("received payload: chain=%s hop=%d bytes=%d sha256=%x payload=%s", input.ChainID, input.Hop, len(input.Payload), sum, input.Payload)
	return nil
}
