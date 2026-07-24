package main

import (
	"context"
	"crypto/sha256"
	"fmt"
	"log"
	"strings"
)

const externalStorageThresholdBytes = 256 * 1024

type GenerateInput struct {
	ChainID   string
	Hop       int
	SizeBytes int
}

func GenerateLargePayloadActivity(_ context.Context, input GenerateInput) (string, error) {
	prefix := fmt.Sprintf("chain=%s hop=%d ", input.ChainID, input.Hop)
	if input.SizeBytes < len(prefix) {
		return "", fmt.Errorf("payload size %d is smaller than prefix", input.SizeBytes)
	}
	payload := prefix + strings.Repeat("payload-data-", (input.SizeBytes/len("payload-data-"))+1)
	return payload[:input.SizeBytes], nil
}

// PrintPayloadActivity validates the application payload after the Temporal SDK
// has transparently hydrated any external-storage reference from MinIO.
func PrintPayloadActivity(ctx context.Context, input RelayInput) error {
	payload := []byte(input.Payload)
	sum := sha256.Sum256(payload)
	log.Printf("received payload: chain=%s hop=%d bytes=%d sha256=%x payload=%s", input.ChainID, input.Hop, len(payload), sum, payload)
	return nil
}

func payloadSHA256(payload string) string {
	sum := sha256.Sum256([]byte(payload))
	return fmt.Sprintf("%x", sum[:])
}
