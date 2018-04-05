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
