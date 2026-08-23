(defsystem "mcp-backend-stdio"
  :version "0.1.0"
  :description "stdio transport backend for mcp-protocol"
  :author "egao1980"
  :license "MIT"
  :depends-on ("mcp-protocol" "rpc-protocol")
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
