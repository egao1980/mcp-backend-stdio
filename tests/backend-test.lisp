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
