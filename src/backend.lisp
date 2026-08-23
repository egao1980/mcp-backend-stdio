(in-package #:mcp-backend-stdio)

(defclass stdio-mcp-backend (mcp-protocol:mcp-backend) ())

(defun make-stdio-mcp-backend ()
  (make-instance 'stdio-mcp-backend))

(defun use-stdio-mcp-backend ()
  (setf mcp-protocol:*mcp-backend* (make-stdio-mcp-backend)))
