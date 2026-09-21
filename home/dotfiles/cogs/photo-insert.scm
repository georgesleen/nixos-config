;; photo-insert: choose a picture, name it, file it into the document's
;; repository, and write its markdown link at the cursor.
;;
;; space i opens a submenu (home/dotfiles/helix.nix), one entry per way of
;; choosing the file: the directory browsed last, a directory typed on the
;; spot, the Taildrop inbox, or the next photo waiting in the inbox with no
;; browsing at all.
;;
;; The phone sends a photo over the tailnet (share sheet, Tailscale, this
;; host), and modules/features/taildrop.nix drops it in ~/Pictures/taildrop.
;; md-photo-pick drains that inbox on every run, so a photo shared seconds ago
;; is on disk before anything is listed.
;;
;; Two programs do the work: md-photo-pick chooses the file, md-photo-import
;; files it and prints the link. This asks for the name between them, and
;; offers the camera's own stem (IMG_1975), so Enter alone keeps that name.
;;
;; The picker runs on a worker thread, because the explorer stays open for as
;; long as the user browses and the editor must keep running.

(require (only-in "helix/static.scm" insert_string))
(require "helix/components.scm")
(require "helix/editor.scm")
;; set-status! and the callback queue live here, not in editor.scm.
(require "helix/misc.scm")
;; hx.block-on-task hands a worker thread's result to the editor thread.
(require "helix/ext.scm")
(require-builtin steel/process)
(require-builtin steel/strings)

(provide photo-insert
         photo-insert-in
         photo-insert-taildrop
         photo-insert-next)

;; How often the editor is woken while the picker runs, and how many ticks it
;; waits before it gives up. 250 ms for 1200 ticks is five minutes.
(define *poll-interval-ms* 250)
(define *poll-limit* 1200)

;; The picker's outcome, editor thread only: 'idle when nothing runs,
;; 'waiting while the picker runs, the chosen path when it chose one, and #f
;; when it did not. A path is never confused with a state, because both states
;; are symbols.
(define *outcome* 'idle)

;; Path of the focused document, or #f for a scratch buffer. md-photo-import
;; needs it to find the repository and to make the link relative.
(define (current-buffer-path)
  (let ((doc (editor->doc-id (editor-focus))))
    (and doc (editor-document->path doc))))

;; stdout of a command, or #f if it could not be run. Stdout is piped so
;; neither program writes over the editor's terminal.
(define (captured-output program arguments)
  (let ((spawned (spawn-process
                  (set-stdout-piped! (command program arguments)))))
    (if (Err? spawned)
        #f
        (let ((finished (wait->stdout (Ok->value spawned))))
          (if (Err? finished) #f (Ok->value finished))))))

;; Trailing newline from a printf; inserting it would split the line the
;; cursor sits on.
(define (trim-trailing-newline text)
  (if (and (> (string-length text) 0)
           (equal? #\newline (string-ref text (- (string-length text) 1))))
      (substring text 0 (- (string-length text) 1))
      text))

(define (base-name path)
  (let ((segments (split-many path "/")))
    (if (empty? segments) path (last segments))))

;; File name without its extension: the name the camera gave the file, which
;; is what the prompt offers to replace.
(define (file-stem path)
  (let* ((name (base-name path))
         (segments (split-many name ".")))
    (if (< (length segments) 2)
        name
        (string-join (take segments (- (length segments) 1)) "."))))

(define (elapsed-seconds ticks)
  (quotient (* ticks *poll-interval-ms*) 1000))

;; Re-arm a timer until the picker finishes. This is what wakes the editor: a
;; callback queued from a worker thread is drained only when the event loop
;; wakes, so without it the name prompt would not appear until the next
;; keypress.
(define (keep-awake! ticks finish!)
  (if (equal? 'waiting *outcome*)
      (if (> ticks *poll-limit*)
          (begin
            (set! *outcome* 'idle)
            (set-status!
             (string-append "photo-insert: gave up waiting after "
                            (number->string (elapsed-seconds ticks))
                            "s")))
          (begin
            (set-status!
             (string-append "photo-insert: explorer open ("
                            (number->string (elapsed-seconds ticks))
                            "s)"))
            (enqueue-thread-local-callback-with-delay
             *poll-interval-ms*
             (lambda () (keep-awake! (+ ticks 1) finish!)))))
      (let ((outcome *outcome*))
        (set! *outcome* 'idle)
        (finish! outcome))))

;; Run md-photo-pick on a worker thread; finish! runs on the editor thread
;; with the chosen path, or #f when nothing was chosen. The worker thread only
;; stores its result, and the timer above hands it on, so every component is
;; pushed from an ordinary editor callback.
(define (pick-file! arguments finish!)
  (if (equal? 'waiting *outcome*)
      (set-status! "photo-insert: the explorer is already open")
      (begin
        (set! *outcome* 'waiting)
        (set-status! "photo-insert: explorer open")
        (spawn-native-thread
         (lambda ()
           (let ((output (captured-output "md-photo-pick" arguments)))
             (hx.block-on-task
              (lambda ()
                ;; A result that arrives after the wait was given up is
                ;; dropped, so it cannot land on the next invocation.
                (when (equal? 'waiting *outcome*)
                  (set! *outcome*
                        (if (and (string? output)
                                 (not (equal? "" (trim-trailing-newline output))))
                            (trim-trailing-newline output)
                            #f))))))))
        (keep-awake! 1 finish!))))

(define (insert-link! path name buffer-path)
  (let ((link (captured-output "md-photo-import"
                               (list "--file" path
                                     "--name" name
                                     "--buffer" buffer-path))))
    (cond ((not link)
           (set-status! "photo-insert: could not run md-photo-import"))
          ((equal? "" (trim-trailing-newline link))
           ;; The importer prints its reason on stderr, which is piped away
           ;; and invisible here.
           (set-status! (string-append "photo-insert: could not file "
                                       (base-name path))))
          (else
           (insert_string (trim-trailing-newline link))))))

;; One prompt for both the file name and the alt text, showing the stock name
;; it replaces. An empty answer is not a cancel: it keeps that stock name.
(define (ask-name! path buffer-path)
  (push-component!
   (prompt (string-append "Name [" (file-stem path) "]: ")
           (lambda (name) (insert-link! path name buffer-path)))))

;; The whole workflow for one set of picker arguments. The buffer path is read
;; before the picker starts, because the user may change buffers while the
;; explorer is open.
(define (photo-insert-from arguments)
  (let ((buffer-path (current-buffer-path)))
    (if (not buffer-path)
        (set-status! "photo-insert: save the buffer first")
        (pick-file! arguments
                    (lambda (path)
                      (if path
                          (ask-name! path buffer-path)
                          (set-status! "photo-insert: no file chosen")))))))

;;@doc
;; Browse for a picture, starting in the directory used last.
(define (photo-insert)
  (photo-insert-from '()))

;;@doc
;; Browse for a picture, starting in a directory you type.
(define (photo-insert-in)
  (if (not (current-buffer-path))
      (set-status! "photo-insert: save the buffer first")
      (push-component!
       (prompt "Directory: "
               (lambda (directory)
                 ;; An empty answer means the remembered directory, which is
                 ;; what plain photo-insert does.
                 (if (equal? "" directory)
                     (photo-insert-from '())
                     (photo-insert-from (list "--dir" directory))))))))

;;@doc
;; Browse for a picture, starting in the Taildrop inbox.
(define (photo-insert-taildrop)
  (photo-insert-from '("--start-inbox")))

;;@doc
;; Insert the oldest photo waiting in the Taildrop inbox, without browsing.
(define (photo-insert-next)
  (photo-insert-from '("--next")))
