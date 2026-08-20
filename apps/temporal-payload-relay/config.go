package main

import (
	"fmt"
	"os"
	"strconv"

	"github.com/Budybot/ob1_tf_gh_budy-common-modules-1_repo_1/go/worker/temporalworker"
)

func workerConfigFromEnv() (temporalworker.Config, error) {
	enableEncryption, err := boolEnv("ENABLE_PAYLOAD_ENCRYPTION", false)
	if err != nil {
		return temporalworker.Config{}, err
	}

	identity := envOr("TEMPORAL_WORKER_IDENTITY", "temporal-payload-relay")
	return temporalworker.Config{
		Address:   envOr("TEMPORAL_HOST", "temporal-frontend.temporal.svc.cluster.local:7233"),
		Namespace: os.Getenv("TEMPORAL_NAMESPACE"),
		TaskQueue: os.Getenv("TEMPORAL_TASK_QUEUE"),
		Identity:  identity,
		// Local relay testing focuses on Vault envelope encryption and Nexus
		// boundaries. MinIO external storage is intentionally disabled.
		EnableExternalPayloadStorage: false,
		EnablePayloadEncryption:      enableEncryption,
		VaultTransitMount:            envOr("VAULT_TRANSIT_MOUNT", "transit"),
		VaultTransitKey:              envOr("VAULT_TRANSIT_KEY", "temporal-payload-relay"),
		NexusEncryptionIdentity: temporalworker.NexusEncryptionIdentity{
			Endpoint: os.Getenv("NEXUS_ENCRYPTION_ENDPOINT"),
		},
	}, nil
}

func envOr(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
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
