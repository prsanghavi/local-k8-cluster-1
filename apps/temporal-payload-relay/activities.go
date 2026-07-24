package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"fmt"
	"io"
	"log"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

const payloadBytes = 320 * 1024

type GenerateInput struct {
	ChainID string
	Hop     int
}
type PersistInput struct {
	ChainID string
	Hop     int
	Payload string
}
type PayloadReference struct {
	Key    string
	Size   int
	SHA256 string
}

func GenerateLargePayloadActivity(_ context.Context, input GenerateInput) (string, error) {
	prefix := fmt.Sprintf("chain=%s hop=%d ", input.ChainID, input.Hop)
	return prefix + strings.Repeat("payload-data-", (payloadBytes/len("payload-data-"))+1), nil
}

// PersistPayloadActivity proves MinIO storage by writing and immediately
// reading metadata for the object. Its large input is also offloaded by the
// Temporal SDK before this activity receives it.
func PersistPayloadActivity(ctx context.Context, input PersistInput) (PayloadReference, error) {
	key := fmt.Sprintf("payload-relay/%s/hop-%d.txt", input.ChainID, input.Hop)
	sum := sha256.Sum256([]byte(input.Payload))
	if _, err := payloadStore.PutObject(ctx, &s3.PutObjectInput{
		Bucket:        aws.String(payloadBucket),
		Key:           aws.String(key),
		Body:          bytes.NewReader([]byte(input.Payload)),
		ContentLength: aws.Int64(int64(len(input.Payload))),
		ContentType:   aws.String("text/plain"),
	}); err != nil {
		return PayloadReference{}, fmt.Errorf("store payload in MinIO: %w", err)
	}
	head, err := payloadStore.HeadObject(ctx, &s3.HeadObjectInput{Bucket: aws.String(payloadBucket), Key: aws.String(key)})
	if err != nil {
		return PayloadReference{}, fmt.Errorf("verify MinIO payload: %w", err)
	}
	if aws.ToInt64(head.ContentLength) != int64(len(input.Payload)) {
		return PayloadReference{}, fmt.Errorf("MinIO payload length %d, want %d", aws.ToInt64(head.ContentLength), len(input.Payload))
	}
	return PayloadReference{Key: key, Size: len(input.Payload), SHA256: fmt.Sprintf("%x", sum[:])}, nil
}

// PrintPayloadActivity loads and validates the MinIO object before logging it.
func PrintPayloadActivity(ctx context.Context, input RelayInput) error {
	object, err := payloadStore.GetObject(ctx, &s3.GetObjectInput{Bucket: aws.String(payloadBucket), Key: aws.String(input.Payload.Key)})
	if err != nil {
		return fmt.Errorf("read payload from MinIO: %w", err)
	}
	defer object.Body.Close()
	payload, err := io.ReadAll(object.Body)
	if err != nil {
		return fmt.Errorf("read MinIO payload body: %w", err)
	}
	sum := sha256.Sum256(payload)
	if len(payload) != input.Payload.Size || fmt.Sprintf("%x", sum[:]) != input.Payload.SHA256 {
		return fmt.Errorf("MinIO payload validation failed for %s", input.Payload.Key)
	}
	log.Printf("received payload: chain=%s hop=%d key=%s bytes=%d sha256=%x payload=%s", input.ChainID, input.Hop, input.Payload.Key, len(payload), sum, payload)
	return nil
}
