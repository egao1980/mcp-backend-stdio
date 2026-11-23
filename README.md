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

While serving, server notifications (`mcp-log`, `send-progress`, `notify-resources-updated`, …) are written on the same stream. They may come from any thread: each line is written under the transport's lock (`rpc-backend-stdio` ≥ 0.1.2).

## Client: server messages, streams, the child (0.3.0)

The client's transport routes what the server sends to mcp-protocol 0.4.0's
handlers: notifications to `mcp-client-handle-notification` (list_changed bumps
`mcp-client-tools-generation` and calls `:on-tools-changed`, `notifications/message`
goes to `:log-handler`, progress to `:progress-handler`, every one to
`:notification-hook`), requests to `mcp-client-handle-request` (ping, `roots/list`
from `:roots`, sampling and elicitation through their handlers; -32601 otherwise),
and writes the answers back. Requests run `:dispatch :concurrent` by default, so a
sampling handler may take its time while the reader keeps routing.

```lisp
;; a child launched on first use
(mcp-protocol:mcp-connect :command '("my-server" "--stdio")
                          :env '(("TOKEN" . "x")) :directory #p"/srv/project/"
                          :error-output #p"/tmp/my-server.log"
                          :log-handler (lambda (m) (format t "[~a] ~a~%"
                                                           (mcp-protocol:mcp-log-message-level m)
                                                           (mcp-protocol:mcp-log-message-data m)))
                          :on-tools-changed (lambda (client) (declare (ignore client)) …)
                          :probe t)

;; a supervised child (supervisor-protocol 0.5.0 channel unit)
(multiple-value-bind (in out) (supervisor-protocol:unit-channel-streams unit)
  (mcp-protocol:mcp-connect :input in :output out :probe t))

(mcp-backend-stdio:close-stdio-mcp-client client)   ; EOF to the server; a :command child is reaped
```

## License

MIT
