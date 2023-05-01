#!/bin/sh
zip submit.zip README.md
zip -r submit.zip scripts
zip -r submit.zip src
zip -r submit.zip test
pandoc final-proj-docs/summary.md -o final-proj-docs/summary.pdf
(cd final-proj-docs && zip ../submit.zip summary.pdf info.rkt)
