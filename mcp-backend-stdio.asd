(defsystem "mcp-backend-stdio"
  :version "0.1.1"
  :description "stdio transport backend for mcp-protocol (newline JSON-RPC)"
  :author "egao1980"
  :license "MIT"
  :depends-on ("mcp-protocol" "rpc-backend-stdio" "rpc-protocol-json")
  :properties (:cl-repo (:ci (:with ("dissect"))))
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "backend"))
  :in-order-to ((test-op (test-op "mcp-backend-stdio/tests"))))

(defsystem "mcp-backend-stdio/tests"
  :depends-on ("mcp-backend-stdio" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "backend-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
