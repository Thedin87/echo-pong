FROM --platform=$BUILDPLATFORM golang:1.25-alpine AS builder

ARG TARGETOS
ARG TARGETARCH

WORKDIR /src
COPY go.mod ./
COPY main.go ./

RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -buildvcs=false -ldflags="-s -w" -o /out/ping-pong .

FROM gcr.io/distroless/static-debian12:nonroot

ENV PORT=8080 \
    SECRET_FILE_PATH=/run/secrets/ping-pong-token

COPY --from=builder /out/ping-pong /ping-pong

EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/ping-pong"]
CMD ["--mode=server"]