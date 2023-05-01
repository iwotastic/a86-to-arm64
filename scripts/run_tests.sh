#!/bin/sh

yes | scripts/copy_course_lang.sh loot

rm -r courselangs/loot/test

cp -R test courselangs/loot

(cd courselangs/loot/test && racket gentests.rkt)

for t in $(cd courselangs/loot/test && echo test*.sh)
do
    (cd courselangs/loot && chmod +x "./test/$t" && "./test/$t")
done
