// cx-grpc-web-shim translates gRPC-Web requests from the local-dev nginx into
// gRPC over HTTP/2 against identity-service, while synthesizing the
// x-coralogix-auth metadata that cx_auth_middleware expects.
//
// In prod, an Istio ingress gateway converts the user's session cookie into
// x-coralogix-auth = base64url(proto AuthContext{user_id, company_id}). We
// have no such gateway locally; instead this shim:
//
//  1. Reads the coralogix_global_session cookie from the incoming HTTP/1.1
//     gRPC-Web request.
//  2. Calls STS /auth/v1/session (cookie-authenticated) on localhost:8084,
//     forwarding the Origin header so STS resolves the right team_id.
//  3. Encodes a minimal AuthContext (user_id + company_id) into protobuf,
//     base64url-encodes it, and sets it as the x-coralogix-auth header.
//  4. Hands the request to grpcweb.WrapServer, which reframes the body and
//     forwards to a transparent gRPC director pointing at identity:6666.
//
// cx_auth_middleware does not verify a signature or expiry on the AuthContext
// value (see common-rs/cx_auth_middleware/src/authz/mod.rs:64-76), so this
// "trusted-gateway" model is sufficient for local dev.
package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/improbable-eng/grpc-web/go/grpcweb"
	"github.com/mwitkow/grpc-proxy/proxy"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/metadata"
)

const (
	sessionCookieName = "coralogix_global_session"
	authHeader        = "x-coralogix-auth"
)

var (
	listenAddr  = flag.String("listen", "127.0.0.1:8085", "address to listen on for gRPC-Web traffic")
	backendAddr = flag.String("backend", "127.0.0.1:6666", "identity-service gRPC address")
	stsURL      = flag.String("sts-url", "http://127.0.0.1:8084/auth/v1/session", "STS session endpoint")
)

// sessionInfo is the subset of STS GlobalSessionInfoResponse we read.
// active_contexts[].user_account_id and team.team_id are integer-typed in
// the model; we accept both number and string forms via json.Number.
type sessionInfo struct {
	Active         bool `json:"active"`
	ActiveContexts []struct {
		UserAccountID json.Number `json:"user_account_id"`
	} `json:"active_contexts"`
	Team *struct {
		Access bool        `json:"access"`
		TeamID json.Number `json:"team_id"`
	} `json:"team"`
}

// encodeAuthContext hand-writes a proto3 wire-format payload for
// AuthContext{user_id (1, string), company_id (2, string)}. We avoid a
// generated proto module so the build stays self-contained.
func encodeAuthContext(userID, companyID string) []byte {
	var buf []byte
	// Field 1, wire type 2 (length-delimited): tag = 1<<3 | 2 = 0x0a.
	buf = append(buf, 0x0a)
	buf = appendVarint(buf, uint64(len(userID)))
	buf = append(buf, []byte(userID)...)
	// Field 2, wire type 2: tag = 2<<3 | 2 = 0x12.
	buf = append(buf, 0x12)
	buf = appendVarint(buf, uint64(len(companyID)))
	buf = append(buf, []byte(companyID)...)
	return buf
}

func appendVarint(buf []byte, v uint64) []byte {
	for v >= 0x80 {
		buf = append(buf, byte(v)|0x80)
		v >>= 7
	}
	return append(buf, byte(v))
}

// fetchAuthHeaderValue calls STS /auth/v1/session and synthesizes
// x-coralogix-auth from the resolved user_id + team_id. Returns "" if the
// session is invalid or no team is granted (caller drops the header so the
// downstream returns its own UNAUTHENTICATED).
func fetchAuthHeaderValue(httpClient *http.Client, cookieValue, origin string) (string, error) {
	req, err := http.NewRequest(http.MethodGet, *stsURL, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("Cookie", sessionCookieName+"="+cookieValue)
	if origin != "" {
		req.Header.Set("Origin", origin)
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("sts %d", resp.StatusCode)
	}
	var info sessionInfo
	if err := json.NewDecoder(resp.Body).Decode(&info); err != nil {
		return "", err
	}
	if !info.Active || len(info.ActiveContexts) == 0 || info.Team == nil || !info.Team.Access {
		return "", fmt.Errorf("no active team session")
	}
	userID := info.ActiveContexts[0].UserAccountID.String()
	teamID := info.Team.TeamID.String()
	if userID == "" || teamID == "" {
		return "", fmt.Errorf("session missing user/team")
	}
	return base64.RawURLEncoding.EncodeToString(encodeAuthContext(userID, teamID)), nil
}

func main() {
	flag.Parse()

	// `grpc.Dial` + `grpc.WithCodec` are deprecated but required: proxy.Codec
	// is a v1 grpc.Codec, and the transparent proxy needs both endpoints to
	// agree on raw byte passthrough. Mirrors the upstream grpcwebproxy
	// (improbable-eng/grpc-web/go/grpcwebproxy).
	//nolint:staticcheck // deprecated codec API is the contract proxy.Codec needs
	backendConn, err := grpc.Dial(
		*backendAddr,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithCodec(proxy.Codec()),
	)
	if err != nil {
		log.Fatalf("dial backend %s: %v", *backendAddr, err)
	}

	director := func(ctx context.Context, fullMethodName string) (context.Context, *grpc.ClientConn, error) {
		md, _ := metadata.FromIncomingContext(ctx)
		// Copy metadata onto the outgoing context so cookies and our injected
		// x-coralogix-auth flow through to identity-service. Drop `connection`
		// (an HTTP/1.1 hop-by-hop header that, if forwarded as gRPC metadata,
		// breaks the HTTP/2 upstream — see improbable-eng/grpc-web#568) and
		// `user-agent` (the gRPC client sets its own).
		mdCopy := md.Copy()
		delete(mdCopy, "user-agent")
		delete(mdCopy, "connection")
		outCtx := metadata.NewOutgoingContext(ctx, mdCopy)
		return outCtx, backendConn, nil
	}

	//nolint:staticcheck // grpc.CustomCodec is the only entry point for v1 grpc.Codec
	grpcSrv := grpc.NewServer(
		grpc.CustomCodec(proxy.Codec()),
		grpc.UnknownServiceHandler(proxy.TransparentHandler(director)),
	)

	wrapped := grpcweb.WrapServer(
		grpcSrv,
		grpcweb.WithOriginFunc(func(string) bool { return true }),
		grpcweb.WithCorsForRegisteredEndpointsOnly(false),
		grpcweb.WithAllowNonRootResource(true),
	)

	stsClient := &http.Client{Timeout: 5 * time.Second}

	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if c, err := r.Cookie(sessionCookieName); err == nil && c.Value != "" {
			if hdr, err := fetchAuthHeaderValue(stsClient, c.Value, r.Header.Get("Origin")); err == nil {
				r.Header.Set(authHeader, hdr)
			} else {
				log.Printf("sts session lookup failed for %s: %v", r.URL.Path, err)
			}
		}
		wrapped.ServeHTTP(w, r)
	})

	srv := &http.Server{
		Addr:              *listenAddr,
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
	}
	log.Printf("cx-grpc-web-shim listening on %s, backend=%s sts=%s", *listenAddr, *backendAddr, *stsURL)
	if err := srv.ListenAndServe(); err != nil {
		log.Fatal(err)
	}
}
