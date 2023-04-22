#lang racket

(require setup/dirs)

(display (string-append (path->string (find-pkgs-dir)) "\n"))
