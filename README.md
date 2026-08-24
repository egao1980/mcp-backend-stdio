# mcp-backend-stdio

stdio (newline JSON-RPC) backend for [`mcp-protocol`](https://github.com/egao1980/mcp-protocol). Wraps [`rpc-backend-stdio`](https://github.com/egao1980/rpc-backend-stdio). Dual-era: modern `2026-07-28` (`server/discover`) and legacy `2025-11-25` (`initialize`).

```lisp
(asdf:load-system "mcp-backend-stdio")
(mcp-backend-stdio:use-stdio-mcp-backend)

;; client (optional :probe t runs mcp-initialize / discover-then-legacy)
(mcp-protocol:mcp-connect :command '("my-mcp-server") :probe t)

;; server on *standard-input* / *standard-output*
(mcp-protocol:mcp-serve (make-instance 'mcp-protocol:mcp-server))
```

## License

MIT
