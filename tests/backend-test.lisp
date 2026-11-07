(in-package #:mcp-backend-stdio/tests)

(deftest backend-class
  (ok (typep (mcp-backend-stdio:make-stdio-mcp-backend)
             'mcp-backend-stdio:stdio-mcp-backend)))

(deftest stdio-serve-discover
  (let* ((server (make-instance 'mcp-protocol:mcp-server
                                :name "stdio-fix" :version "0.1.0"))
         (req (rpc-protocol:encode-request
               "server/discover"
               (mcp-protocol:json-object
                "_meta" (mcp-protocol:json-object
                         "io.modelcontextprotocol/protocolVersion" "2026-07-28"
                         "io.modelcontextprotocol/clientInfo"
                         (mcp-protocol:json-object "name" "t" "version" "0")
                         "io.modelcontextprotocol/clientCapabilities"
                         (mcp-protocol:json-object)))
               :id 1))
         (in (make-string-input-stream (format nil "~a~%" req)))
         (out (make-string-output-stream))
         (backend (mcp-backend-stdio:make-stdio-mcp-backend)))
    (mcp-protocol:backend-mcp-serve backend server :input in :output out)
    (let* ((line (string-trim '(#\newline #\return) (get-output-stream-string out)))
           (msg (rpc-protocol:decode-message line))
           (result (gethash "result" msg)))
      (ok (equal "complete" (gethash "resultType" result)))
      (ok (find "2026-07-28" (coerce (gethash "supportedVersions" result) 'list)
                :test #'string=)))))

(deftest stdio-connect-shape
  (let* ((backend (mcp-backend-stdio:make-stdio-mcp-backend))
         (in (make-string-input-stream ""))
         (out (make-string-output-stream))
         (client (mcp-protocol:backend-mcp-connect backend :input in :output out)))
    (ok (typep client 'mcp-protocol:mcp-client))
    (ok (eq :unknown (mcp-protocol:mcp-client-era client)))
    (ok (typep (mcp-protocol:mcp-client-transport client)
               'rpc-backend-stdio:stdio-rpc-transport))))

(deftest stdio-serve-sends-notifications
  (let* ((server (make-instance 'mcp-protocol:mcp-server :name "notify-fix" :version "0.1.0"))
         (req (rpc-protocol:encode-request
               "tools/call"
               (mcp-protocol:json-object
                "name" "work" "arguments" (mcp-protocol:json-object)
                "_meta" (mcp-protocol:json-object "progressToken" 7))
               :id 1))
         (in (make-string-input-stream (format nil "~a~%" req)))
         (out (make-string-output-stream)))
    (mcp-protocol:register-tool
     server
     (mcp-protocol:make-mcp-tool
      "work" :input-schema (mcp-protocol:json-object "type" "object")
      :handler (lambda (args)
                 (declare (ignore args))
                 (mcp-protocol:send-progress server 1 :total 1)
                 (mcp-protocol:mcp-log server "info" "working")
                 "ok")))
    (mcp-protocol:backend-mcp-serve (mcp-backend-stdio:make-stdio-mcp-backend) server
                                    :input in :output out)
    (let ((msgs (with-input-from-string (s (get-output-stream-string out))
                  (loop for line = (read-line s nil) while line
                        collect (rpc-protocol:decode-message line)))))
      (ok (equal '("notifications/progress" "notifications/message" nil)
                 (mapcar (lambda (m) (gethash "method" m)) msgs)))
      (ok (= 7 (gethash "progressToken" (gethash "params" (first msgs)))))
      (ok (= 1 (gethash "id" (third msgs))))
      ;; the notifier is removed when serving ends
      (ok (null (mcp-protocol:mcp-server-notifier server))))))
