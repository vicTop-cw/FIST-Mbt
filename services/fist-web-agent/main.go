// fist-web-agent: MD 自解压自建服务核心（Go 单二进制，纯标准库）
//
// 端点:
//   GET  /health              -> 存活探针
//   POST /v1/chat/completions -> OpenAI 兼容
//   POST /mcp                 -> JSON-RPC 2.0 网关
//   GET  /api-key             -> 仅 --auth-print 或显式请求时回显 key
//
// 认证: X-API-Key / Authorization: Bearer 双通道（32 位随机 key，--api-key 可注入）
// 治理: heartbeat 写状态文件（--state-dir），供外部 watchdog 探活
//
// 交叉编译: GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o fist-web-agent .
package main

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const (
	serviceID   = "fist-web-agent"
	apiKeyLen   = 32
	heartbeatIn = 60 * time.Second
)

var (
	bindAddr  = flag.String("bind", "127.0.0.1:18646", "listen address")
	apiKey    = flag.String("api-key", "", "explicit api key (32 chars); empty = auto generate")
	authPrint = flag.Bool("auth-print", false, "print api key to stdout once")
	stateDir  = flag.String("state-dir", "", "directory for heartbeat/state files (default: /tmp/fist-web-agent)")
)

type server struct {
	mu      sync.RWMutex
	apiKey  string
	startAt time.Time
	stateDir string
}

func main() {
	flag.Parse()

	s := &server{startAt: time.Now()}
	if s.stateDir = *stateDir; s.stateDir == "" {
		s.stateDir = filepath.Join(os.TempDir(), "fist-web-agent")
	}
	if err := os.MkdirAll(s.stateDir, 0o755); err != nil {
		log.Fatalf("ERR_STATE_DIR: %v", err)
	}

	key := *apiKey
	if key == "" {
		key = genKey(apiKeyLen)
	}
	if len(key) < 16 {
		log.Fatalf("ERR_API_KEY_TOO_SHORT: need >=16 chars, got %d", len(key))
	}
	s.apiKey = key
	if *authPrint {
		fmt.Printf("API-KEY: %s\n", key)
	}

	// 心跳协程
	go s.heartbeatLoop()

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", s.handleHealth)
	mux.HandleFunc("GET /api-key", s.handleAPIKey)
	mux.HandleFunc("POST /v1/chat/completions", s.auth(s.handleChat))
	mux.HandleFunc("POST /mcp", s.auth(s.handleMCP))

	ln, err := net.Listen("tcp", *bindAddr)
	if err != nil {
		log.Fatalf("ERR_LISTEN: %v", err)
	}
	addr := ln.Addr().String()
	pid := os.Getpid()
	fmt.Printf("fist-web-agent alive: pid=%d listen=%s\n", pid, addr)
	s.writeState(map[string]any{
		"service_id": serviceID, "alive": true, "listen_addr": addr,
		"pid": pid, "started_at": s.startAt.UTC().Format(time.RFC3339),
	})
	log.Printf("listening on %s (pid=%d)", addr, pid)
	if err := http.Serve(ln, mux); err != nil {
		log.Fatalf("ERR_SERVE: %v", err)
	}
}

func (s *server) auth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !s.authOK(r) {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusUnauthorized)
			json.NewEncoder(w).Encode(map[string]any{"error": "unauthorized", "message": "invalid or missing api key"})
			return
		}
		next(w, r)
	}
}

func (s *server) authOK(r *http.Request) bool {
	provided := r.Header.Get("X-API-Key")
	if provided == "" {
		authz := r.Header.Get("Authorization")
		if strings.HasPrefix(authz, "Bearer ") {
			provided = strings.TrimPrefix(authz, "Bearer ")
		}
	}
	if provided == "" {
		return false
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	// 常量时间比较
	a := sha256.Sum256([]byte(provided))
	b := sha256.Sum256([]byte(s.apiKey))
	return hex.EncodeToString(a[:]) == hex.EncodeToString(b[:])
}

func (s *server) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{
		"service_id":  serviceID,
		"alive":       true,
		"listen_addr": *bindAddr,
		"pid":         os.Getpid(),
		"uptime_s":    int(time.Since(s.startAt).Seconds()),
	})
}

func (s *server) handleAPIKey(w http.ResponseWriter, r *http.Request) {
	s.mu.RLock()
	key := s.apiKey
	s.mu.RUnlock()
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{"api_key": key})
}

// OpenAI 兼容 /v1/chat/completions
func (s *server) handleChat(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Model    string `json:"model"`
		Messages []struct {
			Role    string `json:"role"`
			Content string `json:"content"`
		} `json:"messages"`
	}
	body, err := io.ReadAll(io.LimitReader(r.Body, 4<<20))
	if err != nil {
		writeErr(w, http.StatusBadRequest, "bad_request", "read body failed")
		return
	}
	if err := json.Unmarshal(body, &req); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid_request", "invalid JSON body")
		return
	}
	if len(req.Messages) == 0 {
		writeErr(w, http.StatusBadRequest, "invalid_request", "messages is empty")
		return
	}
	// 组装回显响应（形状 OpenAI 兼容；推理逻辑由上层接入）
	resp := map[string]any{
		"id":      "chatcmpl-" + genKey(24),
		"object":  "chat.completion",
		"created": time.Now().Unix(),
		"model":   req.Model,
		"choices": []map[string]any{
			{
				"index": 0,
				"message": map[string]any{
					"role":    "assistant",
					"content": "fist-web-agent echo: " + req.Messages[len(req.Messages)-1].Content,
				},
				"finish_reason": "stop",
			},
		},
		"usage": map[string]any{"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

// /mcp JSON-RPC 2.0 网关（骨架：initialize / tools/list / tools/call）
func (s *server) handleMCP(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(io.LimitReader(r.Body, 8<<20))
	if err != nil {
		writeErr(w, http.StatusBadRequest, "bad_request", "read body failed")
		return
	}
	var msg struct {
		JSONRPC string          `json:"jsonrpc"`
		ID      json.RawMessage `json:"id"`
		Method  string          `json:"method"`
		Params  json.RawMessage `json:"params"`
	}
	if err := json.Unmarshal(body, &msg); err != nil || msg.Method == "" {
		writeErr(w, http.StatusBadRequest, "invalid_request", "invalid JSON-RPC")
		return
	}
	switch msg.Method {
	case "initialize":
		writeRPC(w, msg.ID, map[string]any{
			"protocolVersion": "2026-07-28",
			"capabilities":    map[string]any{"tools": map[string]any{}},
			"serverInfo":      map[string]any{"name": serviceID, "version": "0.1.0"},
		})
	case "tools/list":
		writeRPC(w, msg.ID, map[string]any{
			"tools": []map[string]any{
				{"name": "health", "description": "query service health", "inputSchema": map[string]any{"type": "object", "properties": map[string]any{}}},
				{"name": "echo", "description": "echo a message", "inputSchema": map[string]any{"type": "object", "properties": map[string]any{"text": map[string]any{"type": "string"}}}},
			},
		})
	case "tools/call":
		var args struct {
			Name      string          `json:"name"`
			Arguments json.RawMessage `json:"arguments"`
		}
		_ = json.Unmarshal(msg.Params, &args)
		switch args.Name {
		case "health":
			writeRPC(w, msg.ID, map[string]any{"content": []map[string]any{{"type": "text", "text": serviceID + " alive"}}, "isError": false})
		case "echo":
			var a struct{ Text string `json:"text"` }
			_ = json.Unmarshal(args.Arguments, &a)
			writeRPC(w, msg.ID, map[string]any{"content": []map[string]any{{"type": "text", "text": a.Text}}, "isError": false})
		default:
			writeRPCErr(w, msg.ID, -32601, "method not found")
		}
	default:
		writeRPCErr(w, msg.ID, -32601, "method not found")
	}
}

func (s *server) heartbeatLoop() {
	t := time.NewTicker(heartbeatIn)
	defer t.Stop()
	for range t.C {
		s.writeState(map[string]any{
			"service_id": serviceID, "alive": true, "listen_addr": *bindAddr,
			"pid": os.Getpid(), "last_heartbeat": time.Now().UTC().Format(time.RFC3339),
		})
	}
}

func (s *server) writeState(payload map[string]any) {
	b, _ := json.Marshal(payload)
	_ = os.WriteFile(filepath.Join(s.stateDir, "heartbeat.json"), b, 0o644)
	_ = os.WriteFile(filepath.Join(s.stateDir, "svc.pid"), []byte(fmt.Sprintf("%d", os.Getpid())), 0o644)
}

func writeErr(w http.ResponseWriter, code int, etype, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(map[string]any{"error": map[string]any{"type": etype, "message": msg}})
}

func writeRPC(w http.ResponseWriter, id json.RawMessage, result any) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{"jsonrpc": "2.0", "id": id, "result": result})
}

func writeRPCErr(w http.ResponseWriter, id json.RawMessage, code int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{"jsonrpc": "2.0", "id": id, "error": map[string]any{"code": code, "message": msg}})
}

func genKey(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		log.Fatalf("ERR_RAND: %v", err)
	}
	return hex.EncodeToString(b)[:n]
}
