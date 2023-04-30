#lang racket

;; This file is based on the printer.rkt found in the langs package, but has been modified to emit
;; semantically equivalent arm64 assembly. Changes from the original a86 printer.rkt are explained in
;; commments.

(provide/contract
 [asm-string  (-> (listof instruction?) string?)] ; deprecated
 [asm-display (-> (listof instruction?) any)])

(define current-shared?
  (make-parameter #f))

(module* private #f
  (provide current-shared?))

;; Updated require to point to the "real" a86's ast module.
(require a86/ast)

;; Any -> Boolean
(define (reg? x)
  (register? x))

;; Reg -> String
;; Modified to output equivalent Arm registers, this mapping was devised with the help of this
;; StackOverflow post about x86 (https://stackoverflow.com/questions/18024672) and this page from
;; the Arm manual (https://developer.arm.com/documentation/102374/0101/Procedure-Call-Standard).
(define (reg->string r)
  (match r
    ; Returns
    ['rax "x0"]
    ['eax "w0"]
    ['rdx "x1"]

    ; Params
    ['rdi "x0"]
    ['rsi "x1"]
    ['rdx "x2"]
    ['rcx "x3"]

    ; Corruptable/scratch
    ['r8  "x9"]
    ['r9  "x10"]
    ['r10 "x11"]
    ['r11 "x12"]
    ;; Note: In certain spots in this file I use the register x13 because it is not exposed to the
    ;; a86 code and is corruptable, so I use it as my invisible scratch register.
    ;;
    ;; Additionally, x14 is used to hold flags, so that I can detect pushing a return address, so that
    ;; I can properly redirect that functionallity into setting x30 to allow proper return
    ;; functionallity.

    ; Callee-saved
    ['rbx "x19"]
    ['r12 "x20"]
    ['r13 "x21"]
    ['r14 "x22"]
    ['r15 "x23"]
    ['rbp "x24"]

    ; Special registers
    ['rsp "sp"]))

;; Helper function to prefix immediates with # as required by the LLVM assembler.
(define (immediate->string i)
  (string-append "#" (number->string i)))

;; Asm -> String
(define (asm-string a)
  (with-output-to-string (lambda () (asm-display a))))

;; Asm -> Void
(define (asm-display a)
  (define external-labels '())

  ;; Label -> String
  ;; prefix with _ for Mac
  (define label-symbol->string
    (match (system-type 'os)
      ['macosx
       (λ (s) (string-append "_" (symbol->string s)))]
      [_
       (if (current-shared?)
           (λ (s)
                  (if (memq s external-labels)
                      ; hack for ELF64 shared libraries in service of
                      ; calling external functions in asm-interp
                      (string-append (symbol->string s) " wrt ..plt")
                      (symbol->string s)))
           symbol->string)]))

  ;; (U Label Reg) -> String
  (define (jump-target->string t)
    (match t
      [(? reg?) (reg->string t)]
      [(Offset (? reg? r) i)
       (string-append "[" (reg->string r) " + " (number->string i) "]")]
      [_ (label-symbol->string t)]))

  ;; Arg -> String
  (define (arg->string a)
    (match a
      ;; The simple case, just a register
      [(? reg?) (reg->string a)]
      ;; This case has been modified because in Arm assembler. Immediates are required to be prefixed
      ;; by a #
      [(? integer?) (immediate->string a)]
      ;; This case has also been updated for compatibility with the Arm assembler.
      [(Offset (? reg? r) i)
       (string-append "[" (reg->string r) ", " (immediate->string i) "]")]
      ;; We pray that this case is not used
      [(Offset (? label? l) i)
       (string-append "[" (label-symbol->string l) " + " (immediate->string i) "]")]
      ;; Likewise for this
      [(Const l)
       (symbol->string l)]
      ;; And for this.
      [(? exp?) (exp->string a)]))

  ;; Exp -> String
  (define (exp->string e)
    (match e
      [(? integer?) (number->string e)]
      [(Plus e1 e2)
       (string-append "(" (exp->string e1) " + " (exp->string e2) ")")]
      [_ (label-symbol->string e)]))

  (define tab (make-string 8 #\space))

  ;; Instruction -> String
  (define (fancy-instr->string i)
    (let ((s (simple-instr->string i)))
      (if (instruction-annotation i)
          (if (< (string-length s) 40)
              (format "~a~a; ~.s" s (make-string (- 40 (string-length s)) #\space) (instruction-annotation i))
              (format "~a ; ~.s" s (instruction-annotation i)))
          s)))


  ;; Instruction -> String
  (define (simple-instr->string i)
    (match i
      ;;; Metadata and global stuff ;;;

      [(Text)      (string-append tab ".text")]
      [(Data)      (string-append tab "section .data align=8")] ; 8-byte aligned data
      [(Label l) (if (equal? l 'entry)
                      ; If we are the entry label, we need to remember where to return to.
                      (string-append "_entry:\n"
                                     tab "stp x29, x30, [sp, #-16]!\n"
                                     tab "mov x29, sp")
                      (string-append (label-symbol->string l) ":"))]
      [(Global x)  (string-append tab ".global "  (label-symbol->string x))]
      [(Extern l)  (begin0 (string-append tab ".extern " (label-symbol->string l))
                           (set! external-labels (cons l external-labels)))]

      ;;; Simple math instructions ;;;
      ;;; These instructions have been updated to support Arm64's more expressive format for the add
      ;;; and sub instructions. That is, add and sub can have differing source and destination
      ;;; registers, so we just print the first arg twice because that is easy.
      ;;;
      ;;; These instructions also have a transparent second funtionality, they automatically detect
      ;;; stack operations and silently double the operand of stack operations. The reason for this is
      ;;; is to ensurre we obey the 16-byte alignment required by the architecture.

      [(Add a1 a2)
       (match a1
        ['rsp (string-append tab "mov x13, " (arg->string a2) "\n"
                             tab "lsl x13, x13, #1\n" ; Multiply by 2
                             tab "add sp, sp, x13")]
        [a1 (string-append tab "add "
                      (arg->string a1) ", "
                      (arg->string a1) ", "
                      (arg->string a2))])]
      [(Sub a1 a2)
       (match a1
        ['rsp (string-append tab "mov x13, " (arg->string a2) "\n"
                             tab "lsl x13, x13, #1\n" ; Multiply by 2
                             tab "sub sp, sp, x13")]
        [a1 (string-append tab "sub "
                      (arg->string a1) ", "
                      (arg->string a1) ", "
                      (arg->string a2))])]

      ;;; Bitwise and logical math operators ;;;
      [(Sal a1 a2)
       ; Note to self: This translation may not be completely equivalent
       (string-append tab "lsl "
                      (arg->string a1) ", "
                      (arg->string a1) ", "
                      (arg->string a2))]
      [(Sar a1 a2)
       (string-append tab "asr "
                      (arg->string a1) ", "
                      (arg->string a1) ", "
                      (arg->string a2))]
      [(And a1 a2)
       (string-append tab "and "
                      (arg->string a1) ", "
                      (arg->string a1) ", "
                      (arg->string a2))]

      [(Or a1 a2)
       (string-append tab "mov x13, " (arg->string a2) "\n"
                      tab "orr "
                      (arg->string a1) ", "
                      (arg->string a1) ", x13")]

      [(Xor a1 a2)
       (string-append tab "mov x13, " (arg->string a2) "\n"
                      tab "eor "
                      (arg->string a1) ", "
                      (arg->string a1) ", x13")]

      ;;; Move - the first difficult instruction ;;;

      [(Mov a1 a2)
       (match (cons a1 a2)
        ;; Arm doesn't support the `reg <- offset` style move, so we replace with a load
        ; Special case - stack operation
        [(cons (? reg?) (Offset 'rsp (? integer? off))) (string-append tab "ldp xzr, "
                                                                       (arg->string a1) ", [sp, "
                                                                       ; Everything stack-related gets
                                                                       ; multiplied by 2
                                                                       (immediate->string (* off 2))
                                                                       "]")]

        [(cons (? reg?) (Offset _ _)) (string-append tab "ldr "
                                                         (arg->string a1) ", "
                                                         (arg->string a2))]

        ;; Arm doesn't support the `offset <- reg` style move, so we replace with a store
        ; Special case - stack operation
        [(cons (Offset 'rsp (? integer? off)) (? reg?)) (string-append tab "stp xzr, "
                                                                       (arg->string a2) ", [sp, "
                                                                       ; Everything stack-related gets
                                                                       ; multiplied by 2
                                                                       (immediate->string (* off 2))
                                                                       "]")]

        [(cons (Offset _ _) (? reg?)) (string-append tab "str "
                                                         (arg->string a2) ", "
                                                         (arg->string a1))]

        ;; Default case - just translate to an Arm mov
        [_ (string-append tab "mov "
           (arg->string a1) ", "
           (arg->string a2))])]

      ;;; Comparisons and conditional jumps ;;;
      ;;; Unexpectedly, these are actually probably the most trivial translations found in this
      ;;; project, with the exception of cmp itself, but that is to patch the behavior of the
      ;;; assert-codepoint routine.

      [(Cmp a1 a2)
       (if (and (integer? a2) (> a2 4095))
           (string-append tab "ldr x13, =" (number->string a2) "\n"
                          tab "cmp " (arg->string a1) ", x13")
           (string-append tab "cmp "
                          (arg->string a1) ", "
                          (arg->string a2)))]

      ; Special jump to register
      [(Jmp (? reg? l))
       (string-append tab "br "
                      (jump-target->string l))]
      [(Jmp l)
       (string-append tab "b "
                      (jump-target->string l))]

      [(Je l)
       (string-append tab "b.eq "
                      (jump-target->string l))]
      [(Jne l)
       (string-append tab "b.ne "
                      (jump-target->string l))]
      [(Jl l)
       (string-append tab "b.lt "
                      (jump-target->string l))]
      [(Jle l)
       (string-append tab "b.le "
                      (jump-target->string l))]
      [(Jg l)
       (string-append tab "b.gt "
                      (jump-target->string l))]
      [(Jge l)
       (string-append tab "b.ge "
                      (jump-target->string l))]
      [(Jo l)
       (string-append tab "b.vs "
                      (jump-target->string l))]
      [(Jno l)
       (string-append tab "b.vc "
                      (jump-target->string l))]
      [(Jc l)
       (string-append tab "b.cs "
                      (jump-target->string l))]
      [(Jnc l)
       (string-append tab "b.cc "
                      (jump-target->string l))]

      ;;; Conditional moves ;;;
      ;;; There is no direct equivalent of these instructions in Arm64, as a result, we will just
      ;;; rely on the fact that we already have jumps and moves done, so we can just use those.
      [(Cmove dst src)
       (apply string-append
          (map (lambda (i) (string-append (simple-instr->string i) "\n"))
            (let ((nomov (gensym 'nomov))) (seq (Jne nomov)
                                                (Mov dst src)
                                                (Label nomov)))))]
      [(Cmovne dst src)
       (apply string-append
          (map (lambda (i) (string-append (simple-instr->string i) "\n"))
            (let ((nomov (gensym 'nomov))) (seq (Je nomov)
                                                (Mov dst src)
                                                (Label nomov)))))]
      [(Cmovl dst src)
       (apply string-append
          (map (lambda (i) (string-append (simple-instr->string i) "\n"))
            (let ((nomov (gensym 'nomov))) (seq (Jge nomov)
                                                (Mov dst src)
                                                (Label nomov)))))]
      [(Cmovle dst src)
       (apply string-append
          (map (lambda (i) (string-append (simple-instr->string i) "\n"))
            (let ((nomov (gensym 'nomov))) (seq (Jg nomov)
                                                (Mov dst src)
                                                (Label nomov)))))]
      [(Cmovg dst src)
       (apply string-append
          (map (lambda (i) (string-append (simple-instr->string i) "\n"))
            (let ((nomov (gensym 'nomov))) (seq (Jle nomov)
                                                (Mov dst src)
                                                (Label nomov)))))]
      [(Cmovge dst src)
       (apply string-append
          (map (lambda (i) (string-append (simple-instr->string i) "\n"))
            (let ((nomov (gensym 'nomov))) (seq (Jl nomov)
                                                (Mov dst src)
                                                (Label nomov)))))]
      [(Cmovo dst src)
       (apply string-append
          (map (lambda (i) (string-append (simple-instr->string i) "\n"))
            (let ((nomov (gensym 'nomov))) (seq (Jno nomov)
                                                (Mov dst src)
                                                (Label nomov)))))]
      [(Cmovno dst src)
       (apply string-append
          (map (lambda (i) (string-append (simple-instr->string i) "\n"))
            (let ((nomov (gensym 'nomov))) (seq (Jo nomov)
                                                (Mov dst src)
                                                (Label nomov)))))]
      [(Cmovc dst src)
       (apply string-append
          (map (lambda (i) (string-append (simple-instr->string i) "\n"))
            (let ((nomov (gensym 'nomov))) (seq (Jnc nomov)
                                                (Mov dst src)
                                                (Label nomov)))))]
      [(Cmovnc dst src)
       (apply string-append
          (map (lambda (i) (string-append (simple-instr->string i) "\n"))
            (let ((nomov (gensym 'nomov))) (seq (Jc nomov)
                                                (Mov dst src)
                                                (Label nomov)))))]

      ;;; Function calls ;;;

      [(Call l)
       (string-append tab "bl " (jump-target->string l) "\n")]

      [(Ret)
       (let ((should-pop (gensym 'pop)))
            (string-append tab "ldp x29, x30, [sp], #16\n" ; If it is, load the link register
                           tab "ret"))]

      ;;; Stack stuff ;;;

      [(Push a)
       (if (equal? a 'rax)
           ;; This continues my function call detection by or-ing x14 (our return flag register) with
           ;; 10, this means that a successful return address push will result in 0b1111 being in x14.
           (string-append tab "stp x29, x0, [sp, #-16]!\n")
           (string-append tab "mov x13, " (arg->string a) "\n"
                          tab "stp xzr, x13, [sp, #-16]!\n"))]
      [(Pop r)
       (string-append tab "ldp xzr, "
                      (reg->string r)
                      ", [sp], #16")]

      [(Lea d (? offset? x))
       (string-append tab "lea "
                      (arg->string d) ", "
                      (arg->string x))]
      [(Lea d x)
       (string-append (if (equal? d 'rax) (string-append
                        tab "mov x14, #5\n" ; Nifty hack to allow us to try to track function calls
                                            ; This sets a flag that will be picked up in the ret
                                            ; instruction. The reason it is 5 instead of something simple
                                            ; is so that it can't be accidentally set by C.
                        ) "")
                      tab "adr "
                      (arg->string d) ", "
                      (exp->string x))]
      [(Not r)
       (string-append tab "not "
                      (reg->string r))]
      [(Div r)
       (string-append tab "div "
                      (arg->string r))]
      [(Equ x c)
       (string-append tab
                      (symbol->string x)
                      " equ "
                      (number->string c))]

      [(Dd x)
       (string-append tab "dd " (arg->string x))]
      [(Dq x)
       (string-append tab "dq " (arg->string x))]
      ))

  (define (comment->string c)
    (match c
      [(% s)   (string-append (make-string 32 #\space) "; " s)]
      [(%% s)  (string-append tab ";; " s)]
      [(%%% s) (string-append ";;; " s)]))

  (define (line-comment i s)
    (let ((i-str (simple-instr->string i)))
      (let ((pad (make-string (max 1 (- 32 (string-length i-str))) #\space)))
        (string-append i-str pad "; " s))))

  ;; [Listof Instr] -> Void
  (define (instrs-display a)
    (match a
      ['() (void)]
      [(cons (? Comment? c) a)
       (begin (write-string (comment->string c))
              (write-char #\newline)
              (instrs-display a))]
      [(cons i (cons (% s) a))
       (begin (write-string (line-comment i s)) ; a line comment trumps an annotation
              (write-char #\newline)
              (instrs-display a))]
      [(cons i a)
       (begin (write-string (fancy-instr->string i))
              (write-char #\newline)
              (instrs-display a))]))

  ;; entry point will be first label
  (match (findf Label? a)
    [(Label g)
     (begin
       (write-string (string-append
                      ; tab "global " (label-symbol->string g) "\n"
                      tab ".align 2\n"
                      tab ".text\n"))
       (instrs-display a))]
    [_
     (instrs-display a)
     #;
     (error "program does not have an initial label")]))
