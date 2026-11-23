(in-package #:mcp-backend-stdio/tests)

;;; 0.3.0 (egao1980/mcp-backend-stdio#7): the server's notifications and
;;; requests reach the client over a real child. The child is this SBCL (no
;;; init files) loading mcp-backend-stdio from this image's sources and fasls,
;;; then tests/fixtures/fake-server.lisp. It runs once through :COMMAND and once
;;; as a supervisor-protocol channel unit whose streams are passed as :INPUT /
;;; :OUTPUT. Every wait is bounded.

(defun %loaded-system-dirs ()
  (remove-duplicates
   (loop for name in (asdf:already-loaded-systems)
         for dir = (and (not (member name '("asdf" "uiop" "asdf-package-system") :test #'string=))
                        (not (uiop:string-prefix-p "sb-" name))
                        (ignore-errors (asdf:system-source-directory name)))
         when dir collect (uiop:native-namestring dir))
   :test #'string=))

(defun %child-forms ()
  (let ((dirs (%loaded-system-dirs))
        (*print-readably* nil))
    (list "(require :asdf)"
          (format nil "(asdf:initialize-source-registry '(:source-registry ~{(:directory ~s) ~}:ignore-inherited-configuration))"
                  dirs)
          (format nil "(asdf:initialize-output-translations '(:output-translations ~{(~s ~s) ~}:ignore-inherited-configuration))"
                  (loop for d in dirs
                        append (list d (uiop:native-namestring
                                        (asdf:apply-output-translations
                                         (uiop:parse-native-namestring d :ensure-directory t))))))
          "(let ((*standard-output* *error-output*)) (asdf:load-system \"mcp-backend-stdio\"))"
          (format nil "(load ~s)"
                  (uiop:native-namestring
                   (asdf:system-relative-pathname "mcp-backend-stdio/tests"
                                                  "tests/fixtures/fake-server.lisp"))))))

#+sbcl
(defun %fake-server-argv ()
  (append (list (uiop:native-namestring sb-ext:*runtime-pathname*)
                "--core" (uiop:native-namestring sb-ext:*core-pathname*)
                "--noinform" "--no-sysinit" "--no-userinit" "--non-interactive")
          (loop for f in (%child-forms) append (list "--eval" f))))

(defun %wait-until (fn &key (timeout 20))
  (loop with end = (+ (get-internal-real-time) (* timeout internal-time-units-per-second))
        when (funcall fn) return t
        when (> (get-internal-real-time) end) return nil
        do (sleep 0.05)))

(defun %temp-path (name)
  (merge-pathnames (format nil "mcp-stdio-~a-~36r" name (random (expt 36 8) (make-random-state t)))
                   (uiop:temporary-directory)))

(defun %tool-text (result)
  (let ((content (and (hash-table-p result) (gethash "content" result))))
    (and content (plusp (length content)) (gethash "text" (elt content 0)))))

(defclass recorder ()
  ((lock :initform (bt2:make-lock) :reader recorder-lock)
   (logs :initform '() :accessor recorder-logs)
   (changed :initform 0 :accessor recorder-changed)
   (methods :initform '() :accessor recorder-methods)))

(defun %record (recorder slot value)
  (bt2:with-lock-held ((recorder-lock recorder))
    (ecase slot
      (:log (push value (recorder-logs recorder)))
      (:changed (incf (recorder-changed recorder)))
      (:method (push value (recorder-methods recorder))))))

(defun %recording-keys (recorder)
  (list :log-handler (lambda (m)
                       (%record recorder :log (list (mcp-protocol:mcp-log-message-level m)
                                                    (mcp-protocol:mcp-log-message-data m))))
        :on-tools-changed (lambda (client) (declare (ignore client)) (%record recorder :changed t))
        :notification-hook (lambda (client method params)
                             (declare (ignore client params))
                             (%record recorder :method method))
        :roots (list (mcp-protocol:make-mcp-root "file:///work/a" :name "a")
                     (mcp-protocol:make-mcp-root "file:///work/b"))))

(defun %check-server-messages (client recorder)
  "The fake server's poke / roots / sample tools against CLIENT."
  (mcp-protocol:mcp-initialize client)
  (let ((poke (%tool-text (mcp-protocol:call-tool client "poke" nil :timeout 60))))
    (ok (equal "ping answered: {}" poke)
        (format nil "the server's ping request got an answer mid-call: ~s" poke)))
  (ok (%wait-until (lambda () (plusp (recorder-changed recorder))))
      "notifications/tools/list_changed reached ON-TOOLS-CHANGED")
  (ok (= 1 (mcp-protocol:mcp-client-tools-generation client)) "the tools generation was bumped")
  (ok (%wait-until (lambda () (recorder-logs recorder))) "notifications/message reached the log handler")
  (ok (equal '(("warning" "poked")) (recorder-logs recorder)))
  (ok (equal '("notifications/tools/list_changed" "notifications/message")
             (reverse (recorder-methods recorder)))
      "the hook saw both notifications, in order")
  (ok (equal "file:///work/a file:///work/b"
             (%tool-text (mcp-protocol:call-tool client "roots" nil :timeout 60)))
      "roots/list is answered with :ROOTS")
  (ok (equal (format nil "sample error ~d" rpc-protocol:+method-not-found+)
             (%tool-text (mcp-protocol:call-tool client "sample" nil :timeout 60)))
      "sampling without a handler is answered -32601"))

(deftest connect-routes-server-messages-over-command
  #-sbcl (skip "the child is this SBCL")
  #+sbcl
  (let* ((recorder (make-instance 'recorder))
         (stderr (%temp-path "stderr.log"))
         (dir (uiop:ensure-directory-pathname (%temp-path "cwd")))
         (client nil))
    (ensure-directories-exist dir)
    (unwind-protect
         (progn
           (setf client (apply #'mcp-protocol:backend-mcp-connect
                               (mcp-backend-stdio:make-stdio-mcp-backend)
                               :command (%fake-server-argv)
                               :error-output stderr
                               :env '(("FAKE_TOKEN" . "t0k3n"))
                               :directory dir
                               (%recording-keys recorder)))
           (ok (eq :concurrent (rpc-backend-stdio:stdio-rpc-transport-dispatch
                                (mcp-protocol:mcp-client-transport client)))
               "server requests are dispatched :concurrent by default")
           (%check-server-messages client recorder)
           (let ((env (%tool-text (mcp-protocol:call-tool client "env" nil :timeout 60))))
             (ok (search "FAKE_TOKEN=t0k3n" env) (format nil ":env reaches the child: ~s" env))
             (let ((cwd (subseq env (+ (search "CWD=" env) 4))))
               (ok (equal (truename dir) (ignore-errors (truename (uiop:ensure-directory-pathname cwd))))
                   (format nil ":directory is the child's cwd: ~s" cwd))))
           (let ((process (mcp-backend-stdio:stdio-mcp-client-process client)))
             (ok process "the child's process handle")
             (mcp-backend-stdio:close-stdio-mcp-client client :timeout 30)
             (ok (not (process-protocol:alive-p process)) "close reaps the child")
             (ok (eq client (mcp-backend-stdio:close-stdio-mcp-client client)) "close is idempotent"))
           (ok (search "fake-mcp: started" (or (ignore-errors (uiop:read-file-string stderr)) ""))
               ":error-output receives the child's stderr"))
      (when client (mcp-backend-stdio:close-stdio-mcp-client client :force t))
      (uiop:delete-file-if-exists stderr)
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(deftest connect-over-a-supervised-channel-unit
  #-sbcl (skip "the child is this SBCL")
  #+sbcl
  (let* ((recorder (make-instance 'recorder))
         (state (uiop:ensure-directory-pathname (%temp-path "sup")))
         (sup (supervisor-protocol:make-supervisor :state-directory state :exit-hook nil))
         (client nil))
    (unwind-protect
         (let ((unit (supervisor-protocol:start-unit sup :mcp-server
                                                     :command (%fake-server-argv)
                                                     :stdio :channel :restart :never)))
           (multiple-value-bind (input output) (supervisor-protocol:unit-channel-streams unit)
             (setf client (apply #'mcp-protocol:backend-mcp-connect
                                 (mcp-backend-stdio:make-stdio-mcp-backend)
                                 :input input :output output
                                 (%recording-keys recorder))))
           (ok (null (mcp-backend-stdio:stdio-mcp-client-process client))
               "no process of its own over given streams")
           (%check-server-messages client recorder)
           (mcp-backend-stdio:close-stdio-mcp-client client)
           (ok (equal '(:exited 0)
                      (multiple-value-list (supervisor-protocol:wait-unit unit :timeout 30)))
               "closing the client's output ends the server at EOF")
           (ok (%wait-until
                (lambda ()
                  (find-if (lambda (r)
                             (and (eq :stderr (supervisor-protocol:log-record-stream r))
                                  (search "fake-mcp: started"
                                          (princ-to-string (supervisor-protocol:log-record-text r)))))
                           (supervisor-protocol:log-read unit))))
               "the child's stderr is in the unit log"))
      (when client (mcp-backend-stdio:close-stdio-mcp-client client :force t))
      (ignore-errors (supervisor-protocol:shutdown-supervisor sup :grace 0.5 :force-grace 1))
      (uiop:delete-directory-tree state :validate t :if-does-not-exist :ignore))))

(deftest connect-wires-handlers-over-streams
  "Without a child: a notification the peer wrote before any request reaches
the handlers (the reader starts at once over :INPUT / :OUTPUT)."
  (let* ((recorder (make-instance 'recorder))
         (line (rpc-protocol:encode-notification "notifications/tools/list_changed"
                                                 (mcp-protocol:json-object)))
         (in (make-string-input-stream (format nil "~a~%" line)))
         (out (make-string-output-stream))
         (client (apply #'mcp-protocol:backend-mcp-connect
                        (mcp-backend-stdio:make-stdio-mcp-backend)
                        :input in :output out :dispatch :serial
                        (%recording-keys recorder))))
    (unwind-protect
         (progn
           (ok (%wait-until (lambda () (plusp (recorder-changed recorder)))))
           (ok (= 1 (mcp-protocol:mcp-client-tools-generation client)))
           (ok (eq :serial (rpc-backend-stdio:stdio-rpc-transport-dispatch
                            (mcp-protocol:mcp-client-transport client))))
           (ok (= 2 (length (mcp-protocol:mcp-client-roots client))) ":roots reach the client"))
      (mcp-backend-stdio:close-stdio-mcp-client client :force t))))
