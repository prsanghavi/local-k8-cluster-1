FROM golang:1.26-bookworm AS build
WORKDIR /workspace

COPY budy/Github/packages/budy-common-modules /workspace/budy/Github/packages/budy-common-modules
COPY experiments/local-k8-cluster-1/apps/temporal-codec-server /workspace/local-k8-cluster-1/apps/temporal-codec-server

WORKDIR /workspace/local-k8-cluster-1/apps/temporal-codec-server
RUN go mod edit -replace github.com/Budybot/ob1_tf_gh_budy-common-modules-1_repo_1/go/worker=/workspace/budy/Github/packages/budy-common-modules/go/worker \
    && go mod download \
    && CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -o /out/temporal-codec-server .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/temporal-codec-server /temporal-codec-server
USER nonroot:nonroot
ENTRYPOINT ["/temporal-codec-server"]
