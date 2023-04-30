#!/bin/sh

# Existence check
if [ -e "$(racket scripts/get_pkg_dir.rkt)/langs/$1/compile-stdin.rkt" ]; then
    if [ -d "courselangs/$1" ]; then
        echo "$1 directory already exists in courselangs. Delete? (y/N)"

        read -r delete
        if [ "$delete" = "y" ]; then
            echo "Deleting $1..."
            rm -r "courselangs/$1"
        else
            exit 1
        fi
    fi

    echo "Copying lang '$1'..."
    cp -R "$(racket scripts/get_pkg_dir.rkt)/langs/$1" "courselangs/$1"

    echo "Patching compile-stdin.rkt..."
    sed -i "" "s/a86\\/printer/\"..\\/..\\/src\\/printer.rkt\"/g" "courselangs/$1/compile-stdin.rkt"

    echo "Creating arm Makefile..."
    cat > "courselangs/$1/arm.mk" << 'EOF'
CC = gcc

objs = \
EOF
    grep -E "\\t[a-z]*?\\.o" "courselangs/$1/Makefile" >> "courselangs/$1/arm.mk"
    cat >> "courselangs/$1/arm.mk" << 'EOF'

default: runtime.o

runtime.o: $(objs)
	ld -r $(objs) -o runtime.o

%.run: %.o runtime.o
	$(CC) runtime.o $< -o $@

.c.o:
	$(CC) -fPIC -c -g -o $@ $<

.s.o:
	as -o $@ $<

%.s: %.rkt
	cat $< | racket -t compile-stdin.rkt -m > $@

clean:
	rm *.o *.s *.run

%.test: %.run %.rkt
	@test "$(shell ./$(<))" = "$(shell racket $(word 2,$^))"
EOF
	echo "Deleting compiled artefacts..."
	test -d "courselangs/$1/compiled" && rm -r "courselangs/$1/compiled"

else
    echo "lang does not exist"
    exit 1
fi
