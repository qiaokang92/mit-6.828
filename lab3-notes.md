# Lab 3: User Environment

## Prepare

If you're not familiar with GCC's inline assembly grammar, you should read some materials before starting the lab in 
[references](https://pdos.csail.mit.edu/6.828/2017/reference.html).

## Part A: User Environments and Exception Handling

In JOS, `struct Env` is an important data structure, which represents a running process. Its conterpart in Linux is `struct task_struct`. JOS kernel maintains all envs using the following global variables:

```
struct Env *envs = NULL;		// All environments
struct Env *curenv = NULL;		// The current env
static struct Env *env_free_list;	// Free environment list
```

Each `env` has an page directory, which represents its **address space**, an important concpet in virtual memory. `struct Env` stores the virtual address of the pgdir.

```
struct Env {
	struct Trapframe env_tf;	// Saved registers
	struct Env *env_link;		// Next free Env
	envid_t env_id;			// Unique environment identifier
	envid_t env_parent_id;		// env_id of this env's parent
	enum EnvType env_type;		// Indicates special system environments
	unsigned env_status;		// Status of the environment
	uint32_t env_runs;		// Number of times environment has run

	// Address space
	pde_t *env_pgdir;		// Kernel virtual address of page dir
};
```

`env_pgdir` points to a first-level pd.

In **Exercise 1**, we allocate `envs` array with size `NENV`.
So `NENV` is the upper bound of the number of processes in JOS kernel.

We need to map the `envs` array at `UENVS` in kernel virtual space and grant 
read-only for user processes. 
We will see how users access this array later in this lab.

After allocating `envs` array, we need to adjust our `page_init` function to
tag memory used by `envs` as used.
```
	size_t i;
   void *kva = (pages + npages) + (sizeof(struct Env) * NENV);
	for (i = 1; i < npages; i++) {
      // [1, IOPHYSMEM): free
      // [IOPHYSMEM, EXTPHYSMEM): memory hole
      // [EXTPHYSMEM, pages + npages): used by pages array (from boot_alloc())
      if (i >= PGNUM(IOPHYSMEM) && i <= PGNUM(PADDR(kva))) {
         continue;
      }
      pages[i].pp_ref = 0;
      pages[i].pp_link = page_free_list;
      page_free_list = &pages[i];
   }
```
### Running Env

**Exercise 2** finishes `env.c`. 
After that, a basic user environment is ready, 
and a user program can get the control. 
But some more work is needed, see below.

`env_init()` requires that the first call to `env_alloc()` returns envs[0].
So we need to write code like:
```
   for (i = 0; i < NENV; i ++) {
      envs[i].env_status = ENV_FREE;
      envs[i].env_id = 0;
      envs[i].env_link = env_free_list;
      env_free_list = &envs[i];
   }
```

Also need to implement:
- env_setup_vm
- region_alloc
- load_icode
- env_create
- env_run

It's not necessary to copy all code here.

After that, `make qemu-nox` will see infinite loop like this:
```
Physical memory: 131072K available, base = 640K, extended = 130432K
check_page_free_list() succeeded!
check_page_alloc() succeeded!
check_page() succeeded!
check_kern_pgdir() succeeded!
check_page_free_list() succeeded!
check_page_installed_pgdir() succeeded!
[00000000] new env 00001000
6828 decimal is 15254 octal!
Physical memory: 131072K available, base = 640K, extended = 130432K
check_page_free_list() succeeded!
check_page_alloc() succeeded!
check_page() succeeded!
check_kern_pgdir() succeeded!
check_page_free_list() succeeded!
check_page_installed_pgdir() succeeded!
[00000000] new env 00001000
6828 decimal is 15254 octal!
Physical memory: 131072K available, base = 640K, extended = 130432K
check_page_free_list() succeeded!
check_page_alloc() succeeded!
check_page() succeeded!
check_kern_pgdir() succeeded!
check_page_free_list() succeeded!
check_page_installed_pgdir() succeeded!
[00000000] new env 00001000
6828 decimal is 15254 octal!
......
```

This is because the user program hello calls `int 0x30` to invoke a system call.
However, JOS has not setup IDT to handle traps, so kernel will trigger 2nd and
3rd fault, and reboots itself eventually.

### Handling Interrupts

**Exercise 3** asks you to read 
[80386 Programmer's Mannual](https://pdos.csail.mit.edu/6.828/2017/readings/i386/toc.htm), 
chapter 9. 
I admit I didn't read, but it's OK for finishing this lab.

Let's conclude how x86 CPU handle interrupts and exceptions:

IDT:

- x86 allows up to 256 different intr entry points
- intr vector is used to index the IDT(interrupt descriptor table)
- each entry: (destination EIP, destination CS, user/kernel mode) 

TSS:

- TSS contains kernel stack information, ie.,SS and ESP
- when trap happens CPU will switch to this kernel stack
- CPU pushes SS,ESP,EFLAGS,CS,EIP,(err) to this new stack.
- TSS has other fields but is not used in JOS

**Exercise 4** sets up trap handlers in `trapentry.S` and 
install them in IDT in `trap.c`, 
so JOS kernel can handle traps. See github for complete sources.

Let's try to answer some questions:

> (1) What is the purpose of having an individual handler function for each 
exception/interrupt? (i.e., if all exceptions/interrupts were delivered to the 
same handler, what feature that exists in the current implementation could not 
be provided?)

It's obvious that if we use a single handler function for all kinds of traps, 
we cannot tell which trap no. to push into stack. 
Different handler pushed different `$(num)` to kernel stack so we can retrieve 
them later and decide which kind of trap it is.

```
#define TRAPHANDLER_NOEC(name, num)  \ 
.text;                               \
   .globl name;                      \
   .type name, @function;            \
   .align 2;                         \
   name:                             \ 
   pushl $0;                         \
   pushl $(num);                     \
   jmp _alltraps;                    \
.data;                               \
   .long name, num
```
Moreother, it cannot judge when to push a dummy error code onto stack

> (2) Did you have to do anything to make the user/softint
program behave correctly? The grade script expects it to produce a general 
protection fault (trap 13), but softint's code says int 14. 
Why should this produce interrupt vector 13? 
What happens if the kernel actually allows softint's int 14 
instruction to invoke the kernel's page fault 
handler (which is interrupt vector 14)?

The answer is from 
[William Cheaung](https://github.com/william-cheung/mit-6.828-2014/blob/lab3/lab3-note%20(user%20environments%2C%20interrupts%2C%20system%20calls).txt):

> No, we did not have to do anything to make softint behave correctly.  This is because we 
should NOT allow users to invoke exceptions of their choice.  If they could predict an 
exception being called, they could put in malicious code on the stack, which the kernel 
would then read out and execute with kernel privileges.  We instead trigger interrupt 13 
since the user program attempted to violate its privileges.

## Part B: Page Faults, Breakpoints Exceptions, and System Calls

### Page faults and breakpoint exception

**Exercise 5 and 6** ask you to modify `trap_dispatch()` to dispatch page 
fault trap and breakpoint trap.

```
      case T_PGFLT:
         page_fault_handler(tf);
         break;
      case T_BRKPT:
         monitor(tf);
         break;
```
Let's jump to the questions:
> (3) The break point test case will either generate a break point exception
or a general protection fault depending on how you initialized the break point
entry in the IDT (i.e., your call to SETGATE from trap_init). Why? How do you 
need to set it up in order to get the breakpoint exception to work as specified 
above and what incorrect setup would cause it to trigger a general 
protection fault?

If you set `DPL = 3` you will get a break point exception as expected, 
otherwise if `DPL = 0` you will get a general protection fault. 
This is because user programs don't have the rights to trigger a 
`T_BRKPT` trap if `DPL = 3`.

> (4) What do you think is the point of these mechanisms, particularly in 
light of what the user/softint test program does?

These mechanisms enforce permissions.  
They create a "gate" for which the user can make calls to the system via 
exceptions.  Some of these gates are accessible to the users, while others 
are not (as enforced by the DPL in the SETGATE call). 
This protects against malicious user code, which may, for instance, 
insert dangerous code on the stack in hopes that a faulty kernel 
(without protection) may execute this code while in kernel privileges. 
Thankfully, we use the DPL levels in SETGATE to protect against this, 
causing general protection faults when the user attempts to call exceptions 
without the correct privileges.

Q: I don't understand: how malicious user code can have kernel running its 
code in user stack?

In **Exercise 7** we implement a few basic system calls so that `user/hello` 
can work and output strings into the screen.

Challenge: implement syscalls using `sysenter` and `sysexit` instructions
instead of `int 0x30` and `iret`.

// TODO

In **Exersice 8** we try to access the `envs` array in user-level program. 
One usage is to ask the kernel to destroy a user-level process, 
by calling `sys_env_destroy()`.

```
   envid_t envid = sys_getenvid();
	thisenv = &(((struct Env *)envs)[ENVX(envid)]);
```

Then, user programs can access to `struct Env`, e.g., `thisenv->env_id`.

### Page faults and memory protection

Problem: syscall interfaces can let user programs pass pointers to the kernel.
These pointers then will be dereferenced by the kernel:

- if the pointer passed to kernel is invalid (e.g., NULL), the kernel will crash
- user program may not have enough permissions to access the memory that
the pointer points to, but the kernel typically have.

To solve the problem above, JOS check each pointer from user space carefully.

**Exercise 9 and 10** check user provided pointers before dereference them to
avoid page faults in kernel.

We need to implement `user_mem_check`, see `kern/pmap.c`.
