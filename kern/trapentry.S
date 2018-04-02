/* See COPYRIGHT for copyright information. */

#include <inc/mmu.h>
#include <inc/memlayout.h>
#include <inc/trap.h>

###################################################################
# exceptions/interrupts
###################################################################

/* TRAPHANDLER defines a globally-visible function for handling a trap.
 * It pushes a trap number onto the stack, then jumps to _alltraps.
 * Use TRAPHANDLER for traps where the CPU automatically pushes an error code.
 *
 * You shouldn't call a TRAPHANDLER function from C, but you may
 * need to _declare_ one in C (for instance, to get a function pointer
 * during IDT setup).  You can declare the function with
 *   void NAME();
 * where NAME is the argument passed to TRAPHANDLER.
 */
#define TRAPHANDLER(name, num)						\
.text;     \
	.globl name;		/* define global symbol for 'name' */	\
	.type name, @function;	/* symbol type is function */		\
	.align 2;		/* align function definition */		\
	name:			/* function starts here */		\
	pushl $(num);							\
	jmp _alltraps;  \
.data;     \
   .long name, num

/* Use TRAPHANDLER_NOEC for traps where the CPU doesn't push an error code.
 * It pushes a 0 in place of the error code, so the trap frame has the same
 * format in either case.
 */
#define TRAPHANDLER_NOEC(name, num)					\
.text;  \
	.globl name;							\
	.type name, @function;						\
	.align 2;							\
	name:								\
	pushl $0;							\
	pushl $(num);							\
	jmp _alltraps;    \
.data; \
   .long name, num


/*
 * Lab 3: Your code here for generating entry points for the different traps.
 */

.data
.global entry_data
entry_data:
.text
TRAPHANDLER_NOEC(trap_entry0, T_DIVIDE);
TRAPHANDLER_NOEC(trap_entry1, T_DEBUG);
TRAPHANDLER_NOEC(trap_entry2, T_NMI);
TRAPHANDLER_NOEC(trap_entry3, T_BRKPT);
TRAPHANDLER_NOEC(trap_entry4, T_OFLOW);
TRAPHANDLER_NOEC(trap_entry5, T_BOUND);
TRAPHANDLER_NOEC(trap_entry6, T_ILLOP);
TRAPHANDLER_NOEC(trap_entry7, T_DEVICE);
TRAPHANDLER(trap_entry8, T_DBLFLT);
TRAPHANDLER(trap_entry10, T_TSS);
TRAPHANDLER(trap_entry11, T_SEGNP);
TRAPHANDLER(trap_entry12, T_STACK);
TRAPHANDLER(trap_entry13, T_GPFLT);
TRAPHANDLER(trap_entry14, T_PGFLT);
TRAPHANDLER_NOEC(trap_entry16, T_FPERR);
TRAPHANDLER_NOEC(trap_entry17, T_ALIGN);
TRAPHANDLER_NOEC(trap_entry18, T_MCHK);
TRAPHANDLER_NOEC(trap_entry19, T_SIMDERR);
TRAPHANDLER_NOEC(trap_entry48, T_SYSCALL);
.data
   .long 0, 0

/*
 * Lab 3: Your code here for _alltraps
 */

_alltraps:
push %ds
push %es
pushal

movl $GD_KD, %eax
movl %eax, %ds
movl %eax, %es

push %esp
call trap
