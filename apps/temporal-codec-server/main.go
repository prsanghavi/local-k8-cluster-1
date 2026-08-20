package main

import (
	"log"
	"net/http"
	"os"
	"strings"

	"github.com/Budybot/ob1_tf_gh_budy-common-modules-1_repo_1/go/worker/temporalworker"
	"go.temporal.io/sdk/converter"
)

const decodePath = "/codec/decode"

func main() {
	codec, err := temporalworker.NewVaultTransitDecodeOnlyPayloadCodec(temporalworker.VaultTransitDecodeOnlyPayloadCodecConfig{
		VaultTransitMount:     requiredEnv("VAULT_TRANSIT_MOUNT"),
		AllowedSymmetricKeys:  csvEnv("VAULT_ALLOWED_SYMMETRIC_KEYS"),
		AllowedNexusEndpoints: csvEnv("VAULT_ALLOWED_NEXUS_ENDPOINTS"),
	})
	if err != nil {
		log.Fatalf("configure Vault Transit decoder: %v", err)
	}
	handler, err := converter.NewPayloadHTTPHandler(converter.PayloadHTTPHandlerOptions{
		PreStorageCodecs: []converter.PayloadCodec{codec},
	})
	if err != nil {
		log.Fatalf("create Temporal payload handler: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	mux.Handle(decodePath, decodeOnly(handler))

	log.Printf("Temporal codec server listening on :8080%s", decodePath)
	if err := http.ListenAndServe(":8080", mux); err != nil {
		log.Fatalf("serve codec endpoint: %v", err)
	}
}

func decodeOnly(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != decodePath {
			http.NotFound(w, r)
			return
		}
		// Do not log the request body or decoded payload. Local proof-of-concept
		// logging is intentionally limited to the endpoint invocation itself.
		log.Printf("decode request from %s", r.RemoteAddr)
		r.Body = http.MaxBytesReader(w, r.Body, 16<<20)
		next.ServeHTTP(w, r)
	})
}

func csvEnv(name string) []string {
	var values []string
	for _, value := range strings.Split(os.Getenv(name), ",") {
		if value = strings.TrimSpace(value); value != "" {
			values = append(values, value)
		}
	}
	return values
}

func requiredEnv(name string) string {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		log.Fatalf("%s is required", name)
	}
	return value
}
