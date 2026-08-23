(in-package #:mcp-backend-stdio/tests)

(deftest backend-class
  (ok (typep (mcp-backend-stdio:make-stdio-mcp-backend) 'mcp-backend-stdio:stdio-mcp-backend)))
