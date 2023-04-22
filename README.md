# a86 -> arm64
My final project for CMSC430 at the University of Maryland, an ahead-of-time translator from the course's subset of
x86 (known as a86) to arm64.

## System Requirements
- An Apple Silicon Mac (preferably), or an ARM Linux PC (such as a Raspberry Pi)
- The LLVM toolchain (with aliases for `gcc` and `as`)
    - On a Mac, this requires the XCode Command Line Tools
    - On Linux, I don't know how one would go about aquiring this setup
- Racket (the arm64 version that one can get on a Mac using `brew install racket`)
- The [`langs` package](https://www.cs.umd.edu/class/spring2023/cmsc430/Software.html#%28part._langs-package%29)
    - As a direct result of `langs` being meant for x86, the automated tests that raco runs will fail. This is fine.
    Regardless of failure, the important parts of the langs package will be installed and that is all that matters.

## Final setup
Run `scripts/init.sh` to finalize setup of this repo and to check that you meet the system requirements.
