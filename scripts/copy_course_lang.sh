#!/bin/sh

cp -R "$(racket scripts/get_pkg_dir.rkt)/langs/$1" "courselangs/$1"
