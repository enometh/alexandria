;; Copyright (c) 2002-2006, Edward Marco Baringer
;; All rights reserved.

(in-package :alexandria)

(defmacro with-open-file* ((stream filespec &key direction element-type
                                   if-exists if-does-not-exist external-format)
                           &body body)
  "Just like WITH-OPEN-FILE, but NIL values in the keyword arguments
mean to use the default value specified for OPEN."
  (once-only (direction element-type if-exists if-does-not-exist external-format)
    `(with-open-stream
         (,stream (apply #'open ,filespec
                         (append
                          (when ,direction
                            (list :direction ,direction))
                          (list :element-type (or ,element-type
                                                  (default-element-type)))
                          (when ,if-exists
                            (list :if-exists ,if-exists))
                          (when ,if-does-not-exist
                            (list :if-does-not-exist ,if-does-not-exist))
                          (when ,external-format
                            (list :external-format ,external-format)))))
       ,@body)))

(defun default-element-type ()
  ;; On Lispworks, ELEMENT-TYPE :DEFAULT selects the appropriate
  ;; subtype of CHARACTER for the given external format which can
  ;; represent all possible characters.
  #+lispworks :default
  ;; The spec says that OPEN's default ELEMENT-TYPE (when it is not
  ;; specified) is CHARACTER, but on AllegroCL it's (UNSIGNED-BYTE 8).
  ;; No harm done by specifying it on other implementations.
  #-lispworks 'character)

(defmacro with-input-from-file ((stream-name file-name &rest args
                                             &key (direction nil direction-p)
                                             &allow-other-keys)
                                &body body)
  "Evaluate BODY with STREAM-NAME to an input stream on the file
FILE-NAME. ARGS is sent as is to the call to OPEN except EXTERNAL-FORMAT,
which is only sent to WITH-OPEN-FILE when it's not NIL."
  (declare (ignore direction))
  (when direction-p
    (error "Can't specify :DIRECTION for WITH-INPUT-FROM-FILE."))
  `(with-open-file* (,stream-name ,file-name :direction :input ,@args)
     ,@body))

(defmacro with-output-to-file ((stream-name file-name &rest args
                                            &key (direction nil direction-p)
                                            &allow-other-keys)
			       &body body)
  "Evaluate BODY with STREAM-NAME to an output stream on the file
FILE-NAME. ARGS is sent as is to the call to OPEN except EXTERNAL-FORMAT,
which is only sent to WITH-OPEN-FILE when it's not NIL."
  (declare (ignore direction))
  (when direction-p
    (error "Can't specify :DIRECTION for WITH-OUTPUT-TO-FILE."))
  `(with-open-file* (,stream-name ,file-name :direction :output ,@args)
     ,@body))

(defun read-stream-content-into-string (stream &key (buffer-size 4096))
  "Return the \"content\" of STREAM as a fresh string."
  (check-type buffer-size positive-integer)
  (let ((*print-pretty* nil)
        (element-type (stream-element-type stream)))
    (unless (subtypep element-type 'character)
      (setq element-type 'character))
    (with-output-to-string (datum nil :element-type element-type)
      (let ((buffer (make-array buffer-size :element-type element-type)))
        (loop
          :for bytes-read = (read-sequence buffer stream)
          :do (write-sequence buffer datum :start 0 :end bytes-read)
          :while (= bytes-read buffer-size))))))

(defun read-file-into-string (pathname &key (buffer-size 4096) external-format)
  "Return the contents of the file denoted by PATHNAME as a fresh string.

The EXTERNAL-FORMAT parameter will be passed directly to WITH-OPEN-FILE
unless it's NIL, which means the system default."
  (with-input-from-file (file-stream pathname :external-format external-format)
    (read-stream-content-into-string file-stream :buffer-size buffer-size)))

(defun write-string-into-file (string pathname &key (if-exists :error)
                                                    if-does-not-exist
                                                    external-format)
  "Write STRING to PATHNAME.

The EXTERNAL-FORMAT parameter will be passed directly to WITH-OPEN-FILE
unless it's NIL, which means the system default."
  (with-output-to-file (file-stream pathname :if-exists if-exists
                                    :if-does-not-exist if-does-not-exist
                                    :external-format external-format)
    (write-sequence string file-stream)))

(defun read-stream-content-into-byte-vector (stream &key ((%length length))
                                                         (initial-size 4096))
  "Return \"content\" of STREAM as freshly allocated (unsigned-byte 8) vector."
  (check-type length (or null non-negative-integer)) ; for compatibility
  (check-type initial-size non-negative-integer)
  (setf initial-size (or length initial-size))
  (let ((result (make-array initial-size :element-type '(unsigned-byte 8)))
        (bytes-read 0))
    (loop
      (setf bytes-read (read-sequence result stream :start bytes-read))
      (when (and length (>= bytes-read length))
        (return))
      ;; There is no PEEK-BYTE, so we just try to read a byte.
      (let ((next-byte (read-byte stream nil nil)))
        (when (null next-byte)
          (return))
        (let ((new-result (make-array (if (zerop (length result))
                                          4096
                                          (* 2 (length result)))
                                      :element-type '(unsigned-byte 8))))
          (replace new-result result :end1 bytes-read :end2 bytes-read)
          (setf (aref new-result bytes-read) next-byte
                result new-result)
          (incf bytes-read))))
    (if (= bytes-read (length result))
        result
        (subseq result 0 bytes-read))))

(defun read-file-into-byte-vector (pathname)
  "Read PATHNAME into a freshly allocated (unsigned-byte 8) vector."
  (with-input-from-file (stream pathname :element-type '(unsigned-byte 8))
    (read-stream-content-into-byte-vector stream :initial-size (file-length stream))))

(defun write-byte-vector-into-file (bytes pathname &key (if-exists :error)
                                                       if-does-not-exist)
  "Write BYTES to PATHNAME."
  (check-type bytes (vector (unsigned-byte 8)))
  (with-output-to-file (stream pathname :if-exists if-exists
                               :if-does-not-exist if-does-not-exist
                               :element-type '(unsigned-byte 8))
    (write-sequence bytes stream)))

(defun copy-file (from to &key (if-to-exists :supersede)
			       (element-type '(unsigned-byte 8)) finish-output)
  (with-input-from-file (input from :element-type element-type)
    (with-output-to-file (output to :element-type element-type
				    :if-exists if-to-exists)
      (copy-stream input output
                   :element-type element-type
                   :finish-output finish-output))))

(defun copy-stream (input output &key (element-type (stream-element-type input))
                    (buffer-size 4096)
                    (buffer (make-array buffer-size :element-type element-type))
                    (start 0) end
                    finish-output)
  "Reads data from INPUT and writes it to OUTPUT. Both INPUT and OUTPUT must
be streams, they will be passed to READ-SEQUENCE and WRITE-SEQUENCE and must have
compatible element-types."
  (check-type start non-negative-integer)
  (check-type end (or null non-negative-integer))
  (check-type buffer-size positive-integer)
  (when (and end
             (< end start))
    (error "END is smaller than START in ~S" 'copy-stream))
  (let ((output-position 0)
        (input-position 0))
    (unless (zerop start)
      ;; FIXME add platform specific optimization to skip seekable streams
      (loop while (< input-position start)
            do (let ((n (read-sequence buffer input
                                       :end (min (length buffer)
                                                 (- start input-position)))))
                 (when (zerop n)
                   (error "~@<Could not read enough bytes from the input to fulfill ~
                           the :START ~S requirement in ~S.~:@>" 'copy-stream start))
                 (incf input-position n))))
    (assert (= input-position start))
    (loop while (or (null end) (< input-position end))
          do (let ((n (read-sequence buffer input
                                     :end (when end
                                            (min (length buffer)
                                                 (- end input-position))))))
               (when (zerop n)
                 (if end
                     (error "~@<Could not read enough bytes from the input to fulfill ~
                          the :END ~S requirement in ~S.~:@>" 'copy-stream end)
                     (return)))
               (incf input-position n)
               (write-sequence buffer output :end n)
               (incf output-position n)))
    (when finish-output
      (finish-output output))
    output-position))
