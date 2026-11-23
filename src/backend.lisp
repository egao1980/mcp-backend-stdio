(in-package #:mcp-backend-stdio)

;;; Newline-delimited JSON-RPC (rpc-backend-stdio) for mcp-protocol.
;;;
;;; 0.3.0 (egao1980/mcp-backend-stdio#7; cl-stack-code H3e-2a). The client side
;;; a host needs:
;;;
;;; BACKEND-MCP-CONNECT (stdio) &key
;;;   INPUT OUTPUT    the streams to talk over: a supervised child's stdout and
;;;                   stdin (supervisor-protocol's UNIT-CHANNEL-STREAMS → (values
;;;                   input output)), or any character stream pair.
;;;   COMMAND         an argv list; the child is launched on first use through
;;;                   process-protocol (as 0.2). With COMMAND:
;;;     ERROR-OUTPUT  the child's stderr (PROCESS-PROTOCOL:LAUNCH :ERROR-OUTPUT:
;;;                   NIL drops it, a pathname or stream receives it; default
;;;                   :INTERACTIVE, the parent's stderr);
;;;     ENV ENV-MODE  the child's environment (entries (name . value) or
;;;                   "NAME=VALUE"; :MERGE (default) over the parent's, a NIL
;;;                   value unsets; :REPLACE exactly ENV);
;;;     DIRECTORY     the child's working directory (default: the parent's).
;;;   DISPATCH        where the server's messages are handled (rpc-backend-stdio
;;;                   :DISPATCH), default :CONCURRENT: each server request on a
;;;                   thread of its own (a sampling handler may call back into a
;;;                   model, or this client, while the reader keeps routing),
;;;                   notifications on one dispatcher thread in arrival order.
;;;   SAMPLING-HANDLER ELICITATION-HANDLER LOG-HANDLER PROGRESS-HANDLER ROOTS
;;;   ON-TOOLS-CHANGED NOTIFICATION-HOOK
;;;                   the MCP-CLIENT's slots of the same names (mcp-protocol
;;;                   0.4.0): ROOTS a list of MCP-ROOTs; LOG-HANDLER gets an
;;;                   MCP-LOG-MESSAGE; ON-TOOLS-CHANGED (lambda (client));
;;;                   NOTIFICATION-HOOK (lambda (client method params)).
;;;   ERA PROBE NAME VERSION   as 0.2 (PROBE runs MCP-INITIALIZE).
;;;   → the MCP-CLIENT. Its transport routes every notification the server
;;;   sends to MCP-CLIENT-HANDLE-NOTIFICATION and every request to
;;;   MCP-CLIENT-HANDLE-REQUEST, whose result (or RPC-ERROR) is written back
;;;   as the response: ping → {}, roots/list → the roots, sampling and
;;;   elicitation → the handlers (-32601 without one), anything else -32601.
;;;   (MCP-CLIENT-TRANSPORT-HANDLERS gives the two closures.) Over INPUT /
;;;   OUTPUT the reader starts at once, so a notification sent before the
;;;   first request is not lost; with COMMAND it starts with the launch.
;;;
;;; CLOSE-STDIO-MCP-CLIENT CLIENT &key FORCE (TIMEOUT 5): close its transport
;;;   (RPC-BACKEND-STDIO:CLOSE-STDIO-RPC-TRANSPORT: a COMMAND child gets EOF on
;;;   stdin, then is killed after TIMEOUT seconds; FORCE kills at once; the
;;;   reader and handler threads are joined). The streams given as INPUT /
;;;   OUTPUT are closed too; a supervised unit is still the caller's to stop.
;;;   Idempotent. → CLIENT.
;;; STDIO-MCP-CLIENT-PROCESS CLIENT → the COMMAND child's process handle, or
;;;   NIL (streams given, or not launched yet).

(defclass stdio-mcp-backend (mcp-protocol:mcp-backend) ())

(defun make-stdio-mcp-backend ()
  (make-instance 'stdio-mcp-backend))

(defun use-stdio-mcp-backend ()
  (setf mcp-protocol:*mcp-backend* (make-stdio-mcp-backend)))

(defmethod mcp-protocol:backend-mcp-connect
    ((backend stdio-mcp-backend) &key input output command
                                   (error-output :interactive)
                                   env (env-mode :merge) directory
                                   (dispatch :concurrent)
                                   (era :unknown) (probe nil)
                                   name version
                                   roots sampling-handler elicitation-handler
                                   log-handler progress-handler
                                   on-tools-changed notification-hook)
  (let ((client (make-instance 'mcp-protocol:mcp-client
                               :era era
                               :name (or name "cl-stack-mcp")
                               :version (or version "0.1.0")
                               :roots roots
                               :sampling-handler sampling-handler
                               :elicitation-handler elicitation-handler
                               :log-handler log-handler
                               :progress-handler progress-handler
                               :on-tools-changed on-tools-changed
                               :notification-hook notification-hook)))
    ;; The handlers close over the client, so the client exists first; the
    ;; transport (whose reader may start at once) is made with them.
    (multiple-value-bind (on-notification on-request)
        (mcp-protocol:mcp-client-transport-handlers client)
      (setf (mcp-protocol:mcp-client-transport client)
            (rpc-backend-stdio:make-stdio-rpc-transport
             :input input :output output :command command
             :error-output error-output :env env :env-mode env-mode :directory directory
             :dispatch dispatch
             :on-notification on-notification :on-request on-request)))
    (when probe
      (mcp-protocol:mcp-initialize client))
    client))

(defun %stdio-transport (client)
  (let ((transport (mcp-protocol:mcp-client-transport client)))
    (and (typep transport 'rpc-backend-stdio:stdio-rpc-transport) transport)))

(defun close-stdio-mcp-client (client &key force (timeout 5))
  "Close CLIENT's stdio transport (the COMMAND child reaped). Idempotent. → CLIENT."
  (let ((transport (%stdio-transport client)))
    (when transport
      (rpc-backend-stdio:close-stdio-rpc-transport transport :force force :timeout timeout)))
  client)

(defun stdio-mcp-client-process (client)
  "The COMMAND child's process handle, or NIL."
  (let ((transport (%stdio-transport client)))
    (and transport (rpc-backend-stdio:stdio-rpc-transport-process transport))))

(defmethod mcp-protocol:backend-mcp-serve
    ((backend stdio-mcp-backend) server &key input output)
  "Serve SERVER over stdio. While serving, server notifications (log, progress,
resource updates) go out on the same stream from any thread."
  (let ((transport (rpc-backend-stdio:make-stdio-rpc-transport :input input :output output))
        (previous (mcp-protocol:mcp-server-notifier server)))
    (setf (mcp-protocol:mcp-server-notifier server)
          (lambda (method params)
            (rpc-protocol:rpc-notify method params :transport transport)))
    (unwind-protect (mcp-protocol:serve-mcp server :transport transport)
      (setf (mcp-protocol:mcp-server-notifier server) previous))))

(use-stdio-mcp-backend)
