(in-package #:mcp-backend-stdio)

(defclass stdio-mcp-backend (mcp-protocol:mcp-backend) ())

(defun make-stdio-mcp-backend ()
  (make-instance 'stdio-mcp-backend))

(defun use-stdio-mcp-backend ()
  (setf mcp-protocol:*mcp-backend* (make-stdio-mcp-backend)))

(defmethod mcp-protocol:backend-mcp-connect
    ((backend stdio-mcp-backend) &key input output command
                                   (era :unknown) (probe nil)
                                   name version)
  (let ((client (make-instance 'mcp-protocol:mcp-client
                               :transport (rpc-backend-stdio:make-stdio-rpc-transport
                                           :input input :output output :command command)
                               :era era
                               :name (or name "cl-stack-mcp")
                               :version (or version "0.1.0"))))
    (when probe
      (mcp-protocol:mcp-initialize client))
    client))

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
