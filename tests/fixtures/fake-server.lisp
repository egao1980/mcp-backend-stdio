;;; A fake stdio MCP server for mcp-backend-stdio's tests (egao1980/mcp-backend-stdio#7).
;;; Loaded by a bare child SBCL after mcp-backend-stdio. An mcp-protocol server
;;; on a peer-mode rpc-backend-stdio transport, so that, mid-session, a tool
;;; can send the client notifications AND requests and wait for the answers.
;;;   poke    → notifications/tools/list_changed, notifications/message
;;;             (warning "poked"), then a ping request; → "ping answered: {}"
;;;             (or "ping failed: …")
;;;   roots   → roots/list request; → the root URIs joined by spaces
;;;   sample  → sampling/createMessage request (the client has no handler);
;;;             → "sample error CODE"
;;;   env     → "FAKE_TOKEN=<value or unset> CWD=<cwd>"
;;; Its stderr gets "fake-mcp: started".

(in-package :cl-user)

(format *error-output* "fake-mcp: started~%")
(finish-output *error-output*)

(defvar *fake-server* (make-instance 'mcp-protocol:mcp-server :name "fake" :version "1.0.0"))
(defvar *fake-tx* nil)

(defun fake-call (method params)
  (rpc-protocol:rpc-call method params :transport *fake-tx* :timeout 30))

(flet ((obj (&rest kv) (apply #'mcp-protocol:json-object kv))
       (tool (name handler)
         (mcp-protocol:register-tool
          *fake-server*
          (mcp-protocol:make-mcp-tool name :description name
                                           :input-schema (mcp-protocol:json-object "type" "object")
                                           :handler handler))))
  (tool "poke"
        (lambda (args)
          (declare (ignore args))
          (mcp-protocol:mcp-notify *fake-server* "notifications/tools/list_changed" (obj))
          (mcp-protocol:mcp-log *fake-server* "warning" "poked" :logger "fake")
          (handler-case
              (let ((pong (fake-call "ping" (obj))))
                (format nil "ping answered: ~a"
                        (if (and (hash-table-p pong) (zerop (hash-table-count pong))) "{}" pong)))
            (error (e) (format nil "ping failed: ~a" e)))))
  (tool "roots"
        (lambda (args)
          (declare (ignore args))
          (let ((result (fake-call "roots/list" (obj))))
            (format nil "~{~a~^ ~}"
                    (map 'list (lambda (r) (gethash "uri" r))
                         (gethash "roots" result))))))
  (tool "sample"
        (lambda (args)
          (declare (ignore args))
          (handler-case (progn (fake-call "sampling/createMessage" (obj "messages" #()))
                               "sample answered")
            (rpc-protocol:rpc-error (e)
              (format nil "sample error ~a" (rpc-protocol:rpc-error-code e))))))
  (tool "env"
        (lambda (args)
          (declare (ignore args))
          (format nil "FAKE_TOKEN=~a CWD=~a"
                  (or (uiop:getenv "FAKE_TOKEN") "unset")
                  (uiop:native-namestring (uiop:getcwd))))))

(setf *fake-tx*
      (rpc-backend-stdio:make-stdio-rpc-transport
       :dispatch :concurrent
       :on-request (lambda (method params)
                     (handler-case (mcp-protocol:dispatch-mcp-method *fake-server* method params)
                       (mcp-protocol:mcp-error (c)
                         (error 'rpc-protocol:rpc-error
                                :message (or (mcp-protocol:mcp-error-message c) "mcp error")
                                :code (or (mcp-protocol:mcp-error-code c) rpc-protocol:+internal-error+)))))
       :on-notification (lambda (method params)
                          (ignore-errors (mcp-protocol:dispatch-mcp-method *fake-server* method params)))))

(setf (mcp-protocol:mcp-server-notifier *fake-server*)
      (lambda (method params) (rpc-protocol:rpc-notify method params :transport *fake-tx*)))

(rpc-backend-stdio:stdio-rpc-transport-wait-closed *fake-tx*)
