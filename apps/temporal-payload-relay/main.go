package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/Budybot/ob1_tf_gh_budy-common-modules-1_repo_1/go/worker/temporalworker"
	"github.com/nexus-rpc/sdk-go/nexus"
	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/temporalnexus"
	"go.temporal.io/sdk/worker"
)

const (
	nexusServiceName = "payload-relay"
	nexusOperation   = "relay"
)

func main() {
	config, err := workerConfigFromEnv()
	if err != nil {
		log.Fatalf("invalid worker configuration: %v", err)
	}
	service, err := temporalworker.New(temporalworker.RunOptions{Config: config}, registerWorker)
	if err != nil {
		log.Fatalf("create worker: %v", err)
	}
	if err := service.Start(); err != nil {
		log.Fatalf("start worker: %v", err)
	}
	log.Printf("payload relay worker started: namespace=%s task_queue=%s", config.Namespace, config.TaskQueue)

	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGINT, syscall.SIGTERM)
	select {
	case signal := <-signals:
		log.Printf("received %s; stopping", signal)
	case err := <-service.Fatal():
		log.Printf("worker stopped after fatal error: %v", err)
	}
	service.Stop()
}

func registerWorker(w worker.Worker) {
	w.RegisterWorkflow(StartChainWorkflow)
	w.RegisterWorkflow(RelayWorkflow)
	w.RegisterActivity(GenerateLargePayloadActivity)
	w.RegisterActivity(PrintPayloadActivity)

	operation := temporalnexus.MustNewTemporalOperation(temporalnexus.TemporalOperationOptions[RelayInput, ChainResult]{
		Name: nexusOperation,
		Start: func(ctx context.Context, nc temporalnexus.NexusClient, input RelayInput, _ temporalnexus.StartTemporalOperationOptions) (temporalnexus.TemporalOperationResult[ChainResult], error) {
			return temporalnexus.StartWorkflow(ctx, nc, client.StartWorkflowOptions{
				ID: fmt.Sprintf("payload-relay-%s-hop-%d", input.ChainID, input.Hop),
			}, RelayWorkflow, input)
		},
	})

	service := nexus.NewService(nexusServiceName)
	service.MustRegister(operation)
	w.RegisterNexusService(service)
}
