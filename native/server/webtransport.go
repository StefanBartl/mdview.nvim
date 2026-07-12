package main

import (
	"context"
	"crypto/tls"
	"fmt"
	"net/http"

	"github.com/quic-go/quic-go/http3"
	"github.com/quic-go/webtransport-go"

	"github.com/StefanBartl/mdview.nvim/native/server/internal/relay"
)

// wtConn adapts a WebTransport session to relay.Conn. Each broadcast message is
// sent on its own unidirectional stream, so the stream boundary IS the message
// boundary — no length framing needed (a plain byte stream would coalesce/split
// messages). The client reads one incoming uni-stream fully per message.
type wtConn struct {
	ctx     context.Context
	session *webtransport.Session
}

func (w wtConn) Send(payload []byte) error {
	stream, err := w.session.OpenUniStreamSync(w.ctx)
	if err != nil {
		return err
	}
	if _, err := stream.Write(payload); err != nil {
		_ = stream.Close()
		return err
	}
	return stream.Close()
}

// startWebTransport starts an HTTP/3 WebTransport server on addr (UDP) serving a
// single /wt endpoint that joins the same relay.Registry rooms as /ws. It runs
// in a background goroutine and returns immediately. The TCP HTTP server (for
// /update, /ws, static, …) is unaffected — WebTransport is an additional,
// opt-in transport on the same port over UDP.
func startWebTransport(addr string, cert tls.Certificate, registry *relay.Registry, token string) {
	server := &webtransport.Server{
		H3: &http3.Server{
			Addr: addr,
			TLSConfig: &tls.Config{
				Certificates: []tls.Certificate{cert},
				NextProtos:   []string{"h3"},
			},
		},
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/wt", handleWebTransport(server, registry, token))
	server.H3.Handler = mux

	go func() {
		if err := server.ListenAndServe(); err != nil {
			// Non-fatal: the client falls back to WebSocket if WebTransport
			// isn't reachable, so a WT listener failure must not take the
			// process down.
			fmt.Printf("[webtransport] listener error: %v\n", err)
		}
	}()
}

// handleWebTransport upgrades a browser connection to a WebTransport session
// (Origin/token checked the same way as /ws) and joins it to the room for its
// document key. Receive-only from the browser like /ws; content flows in via
// POST /update and is fanned out over per-message uni-streams.
func handleWebTransport(server *webtransport.Server, registry *relay.Registry, token string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !relay.ValidToken(token, r.URL.Query().Get("token")) {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		key := r.URL.Query().Get("key")
		if key == "" {
			http.Error(w, "missing key", http.StatusBadRequest)
			return
		}

		session, err := server.Upgrade(w, r)
		if err != nil {
			return
		}
		defer session.CloseWithError(0, "")

		ctx := session.Context()
		conn := wtConn{ctx: ctx, session: session}
		registry.Join(key, conn)
		defer registry.Leave(key, conn)

		// Seed the newly-joined session with the current document, like /ws.
		if payload, ok := registry.LastPayload(key); ok {
			if err := conn.Send(payload); err != nil {
				return
			}
		}

		// Stay until the client disconnects; broadcasts are pushed via conn.Send.
		<-ctx.Done()
	}
}
