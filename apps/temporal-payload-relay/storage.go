package main

import (
	"fmt"
	"os"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

var payloadStore *s3.Client
var payloadBucket string

func initializePayloadStore() error {
	accessKey, err := os.ReadFile(envOr("EXTERNAL_PAYLOAD_STORAGE_ACCESS_KEY_PATH", "/var/run/secrets/minio/root-user"))
	if err != nil {
		return err
	}
	secretKey, err := os.ReadFile(envOr("EXTERNAL_PAYLOAD_STORAGE_SECRET_KEY_PATH", "/var/run/secrets/minio/root-password"))
	if err != nil {
		return err
	}
	endpoint := envOr("EXTERNAL_PAYLOAD_STORAGE_ENDPOINT", "http://minio.minio.svc.cluster.local:9000")
	payloadBucket = envOr("EXTERNAL_PAYLOAD_STORAGE_BUCKET", "temporal-worker-payloads")
	config := aws.Config{Region: envOr("EXTERNAL_PAYLOAD_STORAGE_REGION", "us-east-1"), Credentials: credentials.NewStaticCredentialsProvider(string(accessKey), string(secretKey), "")}
	payloadStore = s3.NewFromConfig(config, func(options *s3.Options) { options.BaseEndpoint = &endpoint; options.UsePathStyle = true })
	if payloadBucket == "" {
		return fmt.Errorf("external payload bucket is empty")
	}
	return nil
}
