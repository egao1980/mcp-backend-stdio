(defsystem "mcp-backend-stdio"
  :version "0.3.0"
  :description "stdio transport backend for mcp-protocol (newline JSON-RPC): a client over a child's pipes or given streams (a supervised channel unit), the server's notifications and requests routed to the client's handlers, the child's stderr, environment and directory"
  :author "egao1980"
  :license "MIT"
  :depends-on ((:version "mcp-protocol" "0.4.1") (:version "rpc-backend-stdio" "0.4.0") "rpc-protocol-json")
  :properties (:cl-repo (:ci (:with ("dissect"))))
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "backend"))
  :in-order-to ((test-op (test-op "mcp-backend-stdio/tests"))))

(defsystem "mcp-backend-stdio/tests"
  :depends-on ("mcp-backend-stdio" "process-backend-uiop"
               (:version "supervisor-protocol" "0.5.0") "bordeaux-threads" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "backend-test")
               ;; 0.3.0
               (:file "client-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
