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
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	_ "github.com/go-sql-driver/mysql"
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
	listenAddr      = flag.String("listen", "127.0.0.1:8085", "address to listen on for gRPC-Web traffic")
	identityBackend = flag.String("identity-backend", "127.0.0.1:6666", "identity-service gRPC address")
	permsBackend    = flag.String("permissions-backend", "127.0.0.1:9092", "permissions-service gRPC address (HTTP is on :8083, gRPC on :9092)")
	orgsBackend     = flag.String("organisations-backend", "127.0.0.1:9091", "organisations-service gRPC address (HTTP is on :8082, gRPC on :9091)")
	stsURL          = flag.String("sts-url", "http://127.0.0.1:8084/auth/v1/session", "STS session endpoint")
	cacheTTL        = flag.Duration("cache-ttl", 10*time.Second, "TTL for successful STS session lookups")
	negCacheTTL     = flag.Duration("neg-cache-ttl", 2*time.Second, "TTL for failed STS session lookups (cuts hot-loops on logged-out cookies)")
)

// userIDCache memoises the (user_account_id, team_id) → users.id UUID
// lookup. The mapping is stable per team membership, so a long TTL is
// fine; we re-resolve on cache miss only.
type userIDCache struct {
	mu      sync.Mutex
	entries map[string]userIDCacheEntry
}

type userIDCacheEntry struct {
	uuid      string
	expiresAt time.Time
}

func newUserIDCache() *userIDCache { return &userIDCache{entries: map[string]userIDCacheEntry{}} }

func (c *userIDCache) get(key string) (string, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	e, ok := c.entries[key]
	if !ok || time.Now().After(e.expiresAt) {
		delete(c.entries, key)
		return "", false
	}
	return e.uuid, true
}

func (c *userIDCache) put(key, uuid string, ttl time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.entries[key] = userIDCacheEntry{uuid: uuid, expiresAt: time.Now().Add(ttl)}
}

// lookupUserUUID resolves users.id (the per-team membership UUID) for a
// given user_account_id + team_id. Identity-service's handlers query
// `WHERE u.id = ?` against this UUID column; without it, every gRPC call
// 404s with "User not found: <user_account_id>". In prod the AuthContext
// is built upstream of identity-service with users.id already populated;
// our local shim has to do the lookup itself.
func lookupUserUUID(ctx context.Context, db *sql.DB, userAccountID uint64, teamID string) (string, error) {
	const q = `SELECT id FROM users WHERE user_account_id = ? AND company_id = ? AND is_active = 1 LIMIT 1`
	row := db.QueryRowContext(ctx, q, userAccountID, teamID)
	var uuid string
	if err := row.Scan(&uuid); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", fmt.Errorf("no users row for user_account_id=%d team_id=%s", userAccountID, teamID)
		}
		return "", fmt.Errorf("users lookup: %w", err)
	}
	return uuid, nil
}

func openMySQL() (*sql.DB, error) {
	host := os.Getenv("APP_MYSQL_HOST")
	port := os.Getenv("APP_MYSQL_PORT")
	user := os.Getenv("APP_MYSQL_USERNAME")
	pass := os.Getenv("APP_MYSQL_PASSWORD")
	schema := os.Getenv("APP_MYSQL_SCHEMA")
	if host == "" || user == "" || pass == "" {
		return nil, fmt.Errorf("APP_MYSQL_HOST/USERNAME/PASSWORD must be set")
	}
	if port == "" {
		port = "3306"
	}
	if schema == "" {
		schema = "Coralogix"
	}
	host = strings.TrimSuffix(host, ".")
	dsn := fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?parseTime=true&timeout=5s&readTimeout=5s&writeTimeout=5s", user, pass, host, port, schema)
	db, err := sql.Open("mysql", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(8)
	db.SetMaxIdleConns(4)
	db.SetConnMaxLifetime(5 * time.Minute)
	return db, nil
}

// authCache memoises the result of fetchAuthHeaderValue keyed by
// (cookie, origin). STS round-trips dominate the cost of every REST call
// going through nginx auth_request; a short TTL keeps logouts visible
// quickly while collapsing bursts of parallel /api/v1/* polls into one
// upstream call. Negative results are also cached (shorter TTL) so a
// logged-out cookie doesn't trigger a STS lookup per FE re-render.
type authCache struct {
	mu      sync.Mutex
	entries map[string]authCacheEntry
}

type authCacheEntry struct {
	header    string // empty when err != nil
	err       error
	expiresAt time.Time
}

func newAuthCache() *authCache { return &authCache{entries: map[string]authCacheEntry{}} }

func (c *authCache) get(key string) (string, error, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	e, ok := c.entries[key]
	if !ok {
		return "", nil, false
	}
	if time.Now().After(e.expiresAt) {
		delete(c.entries, key)
		return "", nil, false
	}
	return e.header, e.err, true
}

func (c *authCache) put(key, header string, err error, ttl time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.entries[key] = authCacheEntry{header: header, err: err, expiresAt: time.Now().Add(ttl)}
}

// fetchAuthHeaderCached wraps fetchAuthHeaderValue with the TTL cache.
// Errors and successes use distinct TTLs so a flapping STS doesn't pin a
// stale negative for the full positive TTL.
func fetchAuthHeaderCached(cache *authCache, httpClient *http.Client, db *sql.DB, userIDs *userIDCache, cookieValue, origin string) (string, error) {
	key := cookieValue + "|" + origin
	if hdr, err, ok := cache.get(key); ok {
		return hdr, err
	}
	hdr, err := fetchAuthHeaderValue(httpClient, db, userIDs, cookieValue, origin)
	if err != nil {
		cache.put(key, "", err, *negCacheTTL)
	} else {
		cache.put(key, hdr, nil, *cacheTTL)
	}
	return hdr, err
}


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
// AuthContext{user_id (1, string), company_id (2, string),
// credentials (4, Credentials{user_token (2, UserToken{token, company_id})}),
// user_info (8, UserInfo{user_account_id (4, uint32)})}.
// We avoid a generated proto module so the build stays self-contained.
//
// `user_info` is required: identity-service handlers (e.g. GetUserTeams)
// read `auth_context.user_info.user_account_id` directly and reject the
// call as Unauthorized when `user_info` is absent.
//
// `credentials.user_token` is required by permissions-service:
// CheckAllTeamPermissions rejects with INVALID_ARGUMENT
// "Check all user team permissions is only allowed for user token auth"
// unless `credentials.sealed_value == user_token`. We pack the global
// session JWT as the token so the auth path matches what Istio injects
// in prod.
func encodeAuthContext(userID, companyID, sessionJWT string, userAccountID uint64) []byte {
	var buf []byte
	// Field 1: user_id (string).
	buf = append(buf, 0x0a)
	buf = appendVarint(buf, uint64(len(userID)))
	buf = append(buf, []byte(userID)...)
	// Field 2: company_id (string).
	buf = append(buf, 0x12)
	buf = appendVarint(buf, uint64(len(companyID)))
	buf = append(buf, []byte(companyID)...)
	// Field 4: credentials (message Credentials).
	// Credentials.sealed_value oneof, field 2 = user_token (message UserToken).
	// UserToken { token (1, string), company_id (2, string) }.
	userToken := []byte{0x0a}
	userToken = appendVarint(userToken, uint64(len(sessionJWT)))
	userToken = append(userToken, []byte(sessionJWT)...)
	userToken = append(userToken, 0x12)
	userToken = appendVarint(userToken, uint64(len(companyID)))
	userToken = append(userToken, []byte(companyID)...)
	credentials := []byte{0x12} // tag for field 2 (user_token), wire type 2
	credentials = appendVarint(credentials, uint64(len(userToken)))
	credentials = append(credentials, userToken...)
	buf = append(buf, 0x22) // tag for field 4 (credentials), wire type 2
	buf = appendVarint(buf, uint64(len(credentials)))
	buf = append(buf, credentials...)
	// Field 8: user_info (message UserInfo) — only user_account_id.
	userInfo := []byte{0x20}
	userInfo = appendVarint(userInfo, userAccountID)
	buf = append(buf, 0x42)
	buf = appendVarint(buf, uint64(len(userInfo)))
	buf = append(buf, userInfo...)
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
//
// The proto AuthContext field 1 (`user_id`) is the per-team membership
// UUID from the `users` table (`users.id`), NOT the user_account_id.
// Identity-service handlers join `users.id = ?` against this UUID column;
// passing the user_account_id integer makes them 404 with
// "User not found: <user_account_id>". We therefore look up the UUID
// from MySQL keyed by (user_account_id, team_id). The lookup is cached
// in `userIDs` since the mapping is stable per team membership.
func fetchAuthHeaderValue(httpClient *http.Client, db *sql.DB, userIDs *userIDCache, cookieValue, origin string) (string, error) {
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
	teamID := info.Team.TeamID.String()
	userAccountID, err := info.ActiveContexts[0].UserAccountID.Int64()
	if err != nil || userAccountID == 0 || teamID == "" {
		return "", fmt.Errorf("session missing user/team")
	}
	cacheKey := fmt.Sprintf("%d|%s", userAccountID, teamID)
	userUUID, ok := userIDs.get(cacheKey)
	if !ok {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		userUUID, err = lookupUserUUID(ctx, db, uint64(userAccountID), teamID)
		if err != nil {
			return "", fmt.Errorf("resolve users.id: %w", err)
		}
		userIDs.put(cacheKey, userUUID, 5*time.Minute)
	}
	return base64.RawURLEncoding.EncodeToString(encodeAuthContext(userUUID, teamID, cookieValue, uint64(userAccountID))), nil
}

func dialBackend(addr string) *grpc.ClientConn {
	// `grpc.Dial` + `grpc.WithCodec` are deprecated but required: proxy.Codec
	// is a v1 grpc.Codec, and the transparent proxy needs both endpoints to
	// agree on raw byte passthrough. Mirrors the upstream grpcwebproxy
	// (improbable-eng/grpc-web/go/grpcwebproxy).
	//nolint:staticcheck // deprecated codec API is the contract proxy.Codec needs
	conn, err := grpc.Dial(
		addr,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithCodec(proxy.Codec()),
	)
	if err != nil {
		log.Fatalf("dial backend %s: %v", addr, err)
	}
	return conn
}

func main() {
	flag.Parse()

	identityConn := dialBackend(*identityBackend)
	permsConn := dialBackend(*permsBackend)
	orgsConn := dialBackend(*orgsBackend)

	// Route by service-prefix. Identity is the default fallback so an
	// unrecognised service still hits a real backend rather than silently
	// 204-ing through a Vite catch-all.
	routes := []struct {
		prefix string
		conn   *grpc.ClientConn
	}{
		{"/com.coralogix.permissions.", permsConn},
		{"/com.coralogix.landingpage.", permsConn},
		{"/com.coralogix.organisations.", orgsConn},
		{"/com.coralogix.provisioning.", orgsConn},
		{"/com.coralogixapis.aaa.organisations.", orgsConn},
		{"/com.coralogixapis.aaa.", permsConn},
		{"/com.coralogix.apikeys.", permsConn},
		{"/com.coralogix.users.v1.UserAccountInfoService", permsConn},
		{"/com.coralogix.identity.", identityConn},
	}

	director := func(ctx context.Context, fullMethodName string) (context.Context, *grpc.ClientConn, error) {
		md, _ := metadata.FromIncomingContext(ctx)
		// Copy metadata onto the outgoing context so cookies and our injected
		// x-coralogix-auth flow through to upstream. Drop `connection`
		// (an HTTP/1.1 hop-by-hop header that, if forwarded as gRPC metadata,
		// breaks the HTTP/2 upstream — see improbable-eng/grpc-web#568) and
		// `user-agent` (the gRPC client sets its own).
		mdCopy := md.Copy()
		delete(mdCopy, "user-agent")
		delete(mdCopy, "connection")
		outCtx := metadata.NewOutgoingContext(ctx, mdCopy)
		for _, r := range routes {
			if strings.HasPrefix(fullMethodName, r.prefix) {
				return outCtx, r.conn, nil
			}
		}
		return outCtx, identityConn, nil
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
	cache := newAuthCache()
	userIDs := newUserIDCache()
	db, err := openMySQL()
	if err != nil {
		log.Fatalf("mysql open: %v", err)
	}
	defer db.Close()

	// /auth-context is for nginx `auth_request`. nginx forwards the client's
	// cookies + Origin in the subrequest; we mint x-coralogix-auth from the
	// session cookie and return it as a response header. nginx then reads
	// that header into a variable and re-emits it on the upstream request to
	// webapi (or any other REST service that expects the AuthContext).
	// Returns 200 with the header on success, 401 if the cookie is missing
	// or STS rejects, so an unauthenticated request is short-circuited
	// before nginx ever calls the upstream.
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/auth-context" {
			c, err := r.Cookie(sessionCookieName)
			if err != nil || c.Value == "" {
				w.WriteHeader(http.StatusUnauthorized)
				return
			}
			hdr, err := fetchAuthHeaderCached(cache, stsClient, db, userIDs, c.Value, r.Header.Get("Origin"))
			if err != nil {
				log.Printf("auth-context sts lookup failed: %v", err)
				w.WriteHeader(http.StatusUnauthorized)
				return
			}
			w.Header().Set(authHeader, hdr)
			w.WriteHeader(http.StatusOK)
			return
		}
		if c, err := r.Cookie(sessionCookieName); err == nil && c.Value != "" {
			if hdr, err := fetchAuthHeaderCached(cache, stsClient, db, userIDs, c.Value, r.Header.Get("Origin")); err == nil {
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
	log.Printf("cx-grpc-web-shim listening on %s, identity=%s permissions=%s sts=%s", *listenAddr, *identityBackend, *permsBackend, *stsURL)
	if err := srv.ListenAndServe(); err != nil {
		log.Fatal(err)
	}
}
