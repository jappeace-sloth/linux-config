;;; emacs-test.el --- tests for the dirvish paste helpers -*- lexical-binding: t; -*-

;; Run with emacs/tests.nix:
;;
;;     nix-build emacs/tests.nix
;;
;; which loads the real emacs.el (through the same default.el the built
;; emacs ships) and then this file, so the tests exercise the config that
;; actually gets installed rather than a copy of it.
;;
;; Scope: the paste logic added for ranger-style yy/p, which is the only
;; part of emacs.el with an algorithm worth asserting (pick a free name,
;; never overwrite, keep counting while names are taken). The rest of the
;; file is package configuration and keybindings, where the value is in
;; whether emacs starts, not in an assertion.
;;
;; dirvish-refresh-listing is deliberately not tested: it is a one line
;; wrapper whose whole content is the arguments it hands to revert-buffer,
;; so a test would be asserting that revert-buffer works, and libraries are
;; assumed to work.

(require 'ert)
(require 'dired)

(defmacro dirvish-test-in-directory (bindings &rest body)
  "Run BODY in a dired buffer on a fresh temporary directory.
BINDINGS is a list of (RELATIVE-NAME . CONTENT) files created there
first. The directory is the current dired listing and is deleted
afterwards, so a test never sees another test's files."
  (declare (indent 1))
  `(let* ((directory (file-name-as-directory (make-temp-file "dirvish-test" t)))
          (dirvish-file-clipboard nil))
     (unwind-protect
         (progn
           (dolist (file ,bindings)
             (with-temp-file (expand-file-name (car file) directory)
               (insert (cdr file))))
           (with-current-buffer (dired-noselect directory)
             (unwind-protect
                 (progn ,@body)
               (kill-buffer))))
       (delete-directory directory t))))

(defun dirvish-test-contents (path)
  "Return the contents of PATH as a string."
  (with-temp-buffer
    (insert-file-contents path)
    (buffer-string)))

(ert-deftest dirvish-paste-free-name-appends-copy ()
  "The first free name for a taken file is the stem plus -copy."
  (dirvish-test-in-directory '(("template.txt" . "content"))
    (should (equal (file-name-nondirectory
                    (dirvish-paste-free-name
                     (expand-file-name "template.txt" directory) directory))
                   "template-copy.txt"))))

(ert-deftest dirvish-paste-free-name-counts-past-taken-names ()
  "Names already on disk are skipped, counting upwards from 2."
  (dirvish-test-in-directory '(("template.txt" . "a")
                               ("template-copy.txt" . "b")
                               ("template-copy-2.txt" . "c"))
    (should (equal (file-name-nondirectory
                    (dirvish-paste-free-name
                     (expand-file-name "template.txt" directory) directory))
                   "template-copy-3.txt"))))

(ert-deftest dirvish-paste-free-name-keeps-the-extension ()
  "The suffix goes before the extension, so the copy opens in the same mode."
  (dirvish-test-in-directory '(("script.sh" . "#!/bin/sh"))
    (should (equal (file-name-nondirectory
                    (dirvish-paste-free-name
                     (expand-file-name "script.sh" directory) directory))
                   "script-copy.sh")))
  (dirvish-test-in-directory '(("README" . "no extension"))
    (should (equal (file-name-nondirectory
                    (dirvish-paste-free-name
                     (expand-file-name "README" directory) directory))
                   "README-copy"))))

(ert-deftest dirvish-paste-clipboard-copies-under-a-free-name ()
  "Pasting into the directory a file came from copies it, it does not overwrite.
Drives the real command, so this covers the collision branch picking a
name and the copy actually landing on disk."
  (dirvish-test-in-directory '(("template.txt" . "original"))
    (setq dirvish-file-clipboard (list (expand-file-name "template.txt" directory)))
    (dirvish-paste-clipboard)
    (should (equal (dirvish-test-contents (expand-file-name "template.txt" directory))
                   "original"))
    (should (equal (dirvish-test-contents (expand-file-name "template-copy.txt" directory))
                   "original"))))

(ert-deftest dirvish-paste-clipboard-repeats-without-overwriting ()
  "One yank pasted three times leaves three copies, not one rewritten copy.
This is the regression that matters: an implementation that reused the
same generated name would pass the single-paste test and lose files here."
  (dirvish-test-in-directory '(("template.txt" . "original"))
    (setq dirvish-file-clipboard (list (expand-file-name "template.txt" directory)))
    (dirvish-paste-clipboard)
    (dirvish-paste-clipboard)
    (dirvish-paste-clipboard)
    (dolist (expected '("template.txt" "template-copy.txt"
                        "template-copy-2.txt" "template-copy-3.txt"))
      (should (equal (dirvish-test-contents (expand-file-name expected directory))
                     "original")))))

(ert-deftest dirvish-paste-clipboard-asks-when-given-a-prefix-argument ()
  "With a prefix argument the name comes from the prompt, not from the generator."
  (dirvish-test-in-directory '(("template.txt" . "original"))
    (setq dirvish-file-clipboard (list (expand-file-name "template.txt" directory)))
    (cl-letf (((symbol-function 'read-string)
               (lambda (&rest _) "named-by-hand.txt")))
      (dirvish-paste-clipboard t))
    (should (equal (dirvish-test-contents
                    (expand-file-name "named-by-hand.txt" directory))
                   "original"))
    (should-not (file-exists-p (expand-file-name "template-copy.txt" directory)))))

(ert-deftest dirvish-paste-clipboard-refuses-an-empty-clipboard ()
  "Pasting with nothing yanked says so instead of failing obscurely."
  (dirvish-test-in-directory '(("template.txt" . "original"))
    (should-error (dirvish-paste-clipboard) :type 'user-error)))

(provide 'emacs-test)
;;; emacs-test.el ends here
