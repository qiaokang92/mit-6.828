# Lab 4: Preemptive Multitasking 

## Part A: Multiprocessor Support and Cooperative Multitasking

### MP support

Some basic knowledge about SMP:
- each CPU has equivalent access to system resources (e.g., CPU, IO buses).
- CPUs have two categories: one BSP and one or more APs
- each CPU has a local APIC (LAPIC).

JOS uses a little chunk of memory at 0XFE000000 to access APIC registers via
MMIO. Since this address is too high we cannot use `KERNBASE` mapping to access
it, we need to map it to a lower virtual address.

In **Exercise 1**, we implement `mmio_map_region` to reserve and map memory to
`MMIOBASE`. It's very similar to function `boot_alloc` in Lab 1.

### AP bootstrap

In `kern/init.c`, `mp_init()` retrieves some MP-related information by reading
MP configuration table in BIOS.

Then `boot_aps()` starts APs. Note that it copies code from `mpentry.S` to
`MPENTRY_PADDR`, which is the entry of APs. `mpentry.S` then calls `mp_main()`.

**Exercise 2** is simple: mark the page at `MPENTRY_PADDR` as used in
`page_init()` to avoid conflicts. Only some adjustment to if condition is needed

```
      if ((i >= PGNUM(IOPHYSMEM) && i <= PGNUM(PADDR((void *)kva)))
          || (i == PGNUM(MPENTRY_PADDR))) {
         continue;
      }
```

As of now, `check_page_free_list()` should pass.

There is a interesting question:

> Compare kern/mpentry.S side by side with boot/boot.S. Bearing in mind that
kern/mpentry.S is compiled and linked to run above KERNBASE just like everything
else in the kernel, what is the purpose of macro MPBOOTPHYS? Why is it necessary
in kern/mpentry.S but not in boot/boot.S? In other words, what could go wrong
if it were omitted in kern/mpentry.S? 
Hint: recall the differences between the link address and the load address
that we have discussed in Lab 1.

We know that `mpentry_start` is a virtual address, so obviously mpentry.S is
linked in a virtual address instead of physical address. However since page
table is not setup at that time, it must use obsolute PADDR to access `gdt` and
other symbols.

In contrast, in `entry.S` we setup page table soon after BSP starts running so
we can just use virtual address.

### Per-CPU State and Initialization

Each CPU has private state, which includes
* kernel stack, see `inc/memlayout.h` for where it is
* TSS and TSS descriptor
* curenv pointer, which points to `struct Env` which is running on this CPU
* registers

In **exercise 3**, we will need to set up per-CPU stack.

```
   int i;
   uint32_t va = KSTACKTOP - KSTKSIZE;
   uint32_t pa;

   for (i = 0; i < NCPU; i ++) {
      pa = PADDR(percpu_kstacks[i]);
      boot_map_region(kern_pgdir, va, KSTKSIZE, pa, PTE_W | PTE_P);
      /* update va to next stack, skip guard page area */
      va = va - (KSTKGAP + KSTKSIZE);
   }
```

In **exercise 4**, we need to initialize TSS and TSS descriptor for each CPU,
which is done in `trap_init_percpu()`.

```
   int i = cpunum();
   cpus[i].cpu_ts.ts_esp0 = KSTACKTOP - i * (KSTKSIZE + KSTKGAP);
   cpus[i].cpu_ts.ts_ss0 = GD_KD;
   gdt[(GD_TSS0 >> 3) + i] = SEG16(STS_T32A,
                                   (uint32_t) (&cpus[i].cpu_ts),
                                   sizeof(struct Taskstate) - 1, 0);
   gdt[(GD_TSS0 >> 3) + i].sd_s = 0;
	ltr(GD_TSS0 + 8 * i);
	// Load the IDT
	lidt(&idt_pd);
```

Remember that TSS contains the address of kernel stack, so what we need to do
here is simply fill kernel stack address in corresponding `ts_esp0` and `ts_ss0`
field.

At this point, if you run `make qemu-nox CPUS=4`, you will see this:

```
[#26#qiaokang@ubuntu ~/mit-6.828]$make qemu-nox CPUS=4
+ cc kern/init.c
+ cc kern/pmap.c
+ ld obj/kern/kernel
+ mk obj/kern/kernel.img
***
*** Use Ctrl-a x to exit qemu
***
qemu-system-i386 -nographic -drive
file=obj/kern/kernel.img,index=0,media=disk,format=raw -serial mon:stdio -gdb
tcp::26000 -D qemu.log -smp 4
6828 decimal is 15254 octal!
Physical memory: 131072K available, base = 640K, extended = 130432K
check_page_free_list() succeeded!
check_page_alloc() succeeded!
check_page() succeeded!
check_kern_pgdir() succeeded!
check_page_free_list() succeeded!
check_page_installed_pgdir() succeeded!
SMP: CPU 0 found 4 CPU(s)
enabled interrupts: 1 2
SMP: CPU 1 starting
SMP: CPU 2 starting
SMP: CPU 3 starting
[00000000] new env 00001000
kernel panic on CPU 0 at kern/trap.c:304: page fault in kernel
Welcome to the JOS kernel monitor!
Type 'help' for a list of commands.
K> QEMU:
```
