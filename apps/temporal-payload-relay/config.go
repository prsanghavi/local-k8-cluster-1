package main

import (
	"fmt"
	"os"
	"strconv"

	"github.com/Budybot/ob1_tf_gh_budy-common-modules-1_repo_1/go/worker/temporalworker"
)

func workerConfigFromEnv() (temporalworker.Config, error) {
	threshold, err := intEnv("EXTERNAL_PAYLOAD_STORAGE_THRESHOLD_BYTES", 256*1024)
	if err != nil {
		return temporalworker.Config{}, err
	}
	maxSize, err := intEnv("EXTERNAL_PAYLOAD_STORAGE_MAX_BYTES", 1024*1024)
	if err != nil {
		return temporalworker.Config{}, err
	}
	enableEncryption, err := boolEnv("ENABLE_PAYLOAD_ENCRYPTION", false)
	if err != nil {
		return temporalworker.Config{}, err
	}

	return temporalworker.Config{
		Address:                                    envOr("TEMPORAL_HOST", "temporal-frontend.temporal.svc.cluster.local:7233"),
		Namespace:                                  os.Getenv("TEMPORAL_NAMESPACE"),
		TaskQueue:                                  os.Getenv("TEMPORAL_TASK_QUEUE"),
		Identity:                                   envOr("TEMPORAL_WORKER_IDENTITY", "temporal-payload-relay"),
		EnableExternalPayloadStorage:               true,
		ExternalPayloadStorageEndpoint:             envOr("EXTERNAL_PAYLOAD_STORAGE_ENDPOINT", "http://minio.minio.svc.cluster.local:9000"),
		ExternalPayloadStorageRegion:               envOr("EXTERNAL_PAYLOAD_STORAGE_REGION", "us-east-1"),
		ExternalPayloadStorageBucket:               envOr("EXTERNAL_PAYLOAD_STORAGE_BUCKET", "temporal-worker-payloads"),
		ExternalPayloadStorageAccessKeyIDPath:      envOr("EXTERNAL_PAYLOAD_STORAGE_ACCESS_KEY_PATH", "/var/run/secrets/minio/root-user"),
		ExternalPayloadStorageSecretAccessKeyPath:  envOr("EXTERNAL_PAYLOAD_STORAGE_SECRET_KEY_PATH", "/var/run/secrets/minio/root-password"),
		ExternalPayloadStoragePayloadSizeThreshold: threshold,
		ExternalPayloadStorageMaxPayloadSize:       maxSize,
		EnablePayloadEncryption:                    enableEncryption,
		VaultTransitMount:                          envOr("VAULT_TRANSIT_MOUNT", "transit"),
		VaultTransitKey:                            envOr("VAULT_TRANSIT_KEY", "temporal-payload-relay"),
	}, nil
}

func envOr(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

func intEnv(name string, fallback int) (int, error) {
	if value := os.Getenv(name); value != "" {
		parsed, err := strconv.Atoi(value)
		if err != nil {
			return 0, fmt.Errorf("parse %s: %w", name, err)
		}
		return parsed, nil
	}
	return fallback, nil
}

func boolEnv(name string, fallback bool) (bool, error) {
	if value := os.Getenv(name); value != "" {
		parsed, err := strconv.ParseBool(value)
		if err != nil {
			return false, fmt.Errorf("parse %s: %w", name, err)
		}
		return parsed, nil
	}
	return fallback, nil
}
