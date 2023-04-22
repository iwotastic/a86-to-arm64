#!/bin/sh

echo "This script will now check to see if your system is compatible with"
echo "a86-to-arm64 and if so, it will bootstrap this repo for your system."
echo ""

echo "| Architecture check"
if [ "$(uname -p)" = "arm" ]; then
    echo " \ {PASS}"
    echo ""
else
    echo " | {FAIL}"
    echo " \ Your architechure does not report itself as arm."
    exit 1
fi

echo "| Racket check"
if test -x "$(which racket)" && test -x "$(which raco)"; then
    echo "|- {PASS}"

    echo " \ Racket architecture check"
    if file "$(which racket)" | grep arm64 > /dev/null; then
        echo "  \ {PASS}"
        echo ""
    else
        echo "  | {FAIL}"
        echo "  | The Racket installed on your system does not appear to be an arm"
        echo "  | executable. Please check to make sure you have the arm version of"
        echo "  \ Racket installed and that it has priority in your PATH."
        exit 1
    fi
else
    echo " | {FAIL}"
    echo " \ Either racket or raco cannot be found on your system."
    exit 1
fi

echo "| LLVM check"
if test -x "$(which gcc)" && test -x "$(which as)"; then
    echo " \ {PASS}"
    echo ""
else
    echo " | {FAIL}"
    echo " \ You don't have \`gcc\` or \`as\` installed."
    exit 1
fi

echo "| \`langs\` package check"
if test -d "$(racket scripts/get_pkg_dir.rkt)/langs"; then
    echo " \ {PASS}"
    echo ""
else
    echo " | {FAIL}"
    echo " \ You don't have the langs package installed on your system."
    exit 1
fi

echo "| Creating \`courselangs\` directory, if it isn't there already"
mkdir -p courselangs
echo " \ {DONE}"
echo ""

echo "... You can run a86-to-arm64. Horray! ..."
