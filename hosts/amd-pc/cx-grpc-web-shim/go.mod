module github.com/coralogix/cx-grpc-web-shim

go 1.24.0

require (
	github.com/go-sql-driver/mysql v1.4.0
	github.com/improbable-eng/grpc-web v0.15.0
	github.com/mwitkow/grpc-proxy v0.0.0-20230212185441-f345521cb9c9
	google.golang.org/grpc v1.55.0
)

require (
	github.com/cenkalti/backoff/v4 v4.1.1 // indirect
	github.com/desertbit/timer v0.0.0-20180107155436-c41aec40b27f // indirect
	github.com/golang/protobuf v1.5.3 // indirect
	github.com/klauspost/compress v1.11.7 // indirect
	github.com/rs/cors v1.7.0 // indirect
	golang.org/x/net v0.8.0 // indirect
	golang.org/x/sys v0.6.0 // indirect
	golang.org/x/text v0.8.0 // indirect
	google.golang.org/appengine v1.6.7 // indirect
	google.golang.org/protobuf v1.30.0 // indirect
	nhooyr.io/websocket v1.8.6 // indirect
)

// Pin pre-split genproto. improbable-eng/grpc-web v0.15.0 references
// google.golang.org/genproto/googleapis/rpc paths that exist in both the
// split-out submodule and the older monolithic package; without this
// constraint `go mod tidy` errors with "ambiguous import".
require google.golang.org/genproto v0.0.0-20230410155749-daa745c078e1 // indirect
