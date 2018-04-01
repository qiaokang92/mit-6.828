# Lab 2: Memory Management

## Part 1: Physical Page Management

This part illustrats how kernel manages physical memeory.

After setting the 4MB page table in entry.S, the kernel now runs at `[KERNBASE,  KERNBASE + 4MB]`, i.e. `[0xf0000000, 0xf0400000]`and can use virtual addresses.

Now let's start to setup our memory!

```
entry.s --> i386_init() --> mem_init()
```

`mem_init()` function is responsible to initialize all memory. At this time, the physical memory layout looks like:

```
+------------------+  <- 0xFFFFFFFF (4GB)
|                  |
|                  |
|   free memory    |
|                  |
|                  |
+------------------+  <- nextfree(va)
|                  |
| memory allocated |
|  by boot_alloc   |   (kern_pgdir and pages are here!)
|                  |
+------------------+  <- end(va)
|                  |
| kernel code/data |
|                  |
+------------------+  <- 0x00100000 (1MB)
|     BIOS ROM     |
+------------------+  <- 0x000F0000 (960KB)
|  16-bit devices, |
|  expansion ROMs  |
+------------------+  <- 0x000C0000 (768KB)
|   VGA Display    |
+------------------+  <- 0x000A0000 (640KB)
|                  |
|    Low Memory    |
|                  |
+------------------+  <- 0x00000000
```
Some important values are used to manage free memory:
1. `end`: The value of virtual address `end` is provided by linker so we know where free va starts.
2. `nextfree` keeps va of the next free page.

Some data structures like `kern_pgdir` and `pages` are allocated in `boot_alloc`.


`pages` is used to track **all** physical memory pages available in RAM. If you have a `struct PageInfo * pp`, you can get the frame index simply using
```
index = pp - pages;
```
Amazing! isn't it?

`page_free_list` is the `head` of free page list.
```
NULL <- pages[i] <- pages[i+1] <- ... <- pages[n] <- page_free_list
```
If there is no free page:
```
NULL <- page_free_list
```

What `page_init()` is to initialize this free list. Note that frame index
```
[PGNUM(IOPHYSMEM), PGNUM(PADDR(pages + npages))]
```
is in use. We don't use `end` to identify the last used page since `end` is a local static variable in `boot_alloc()`:
```
void
page_init(void)
{
   size_t i;
   for (i = 1; i < npages; i++) {
      // [1, IOPHYSMEM]: free
      // [IOPHYSMEM, EXTPHYSMEM): hole
      // [EXTPHYSMEM, pages + npages): used by pages array (from boot_alloc())
      if (i >= PGNUM(IOPHYSMEM) && i <= PGNUM(PADDR(pages + npages))) {
         continue;
      }
      pages[i].pp_ref = 0;
      pages[i].pp_link = page_free_list;
      page_free_list = &pages[i];
   }
}
```

## Part 2: Virtual Memory

Look at the  [Intel 80386 Reference Manual](https://pdos.csail.mit.edu/6.828/2017/readings/i386/toc.htm) for more details of segmentation and paging, as well as the protection mechanism.

In this part, We need to finish a couple of functions. But I will give a more detailed illustration in the next part.

## Part 3: Kernel Address Space

The next step is to map `pages` to `PAGES` area so they can be accessed by user (read-only):
```
   int ret, perm;
   uintptr_t size, offset;
   physaddr_t pa = PADDR(pages);
   size = ROUNDUP(npages * sizeof(struct PageInfo), PGSIZE);
   perm = PTE_U | PTE_P;
   for (offset = 0; offset < size; offset += PGSIZE) {
      ret = page_insert(kern_pgdir, pa2page(pa + offset),
                        (void *)(UPAGES + offset), perm);
      assert(!ret);
   }
```
`page_insert()` is to map a `struct PageInfo` to a specific virtual address, here is `UPAGES`. Note that `pages` may be acroess multiple pages, so we need to use a `for` loop here.

Then map kernel stack using `boot_map_region`:
```
   perm = PTE_P | PTE_W;
   boot_map_region(kern_pgdir, KSTACKTOP-KSTKSIZE,
                   ROUNDUP(KSTKSIZE,PGSIZE),PADDR(bootstack), perm);
```

Finally, map all virtual addresses above in `[KERNBASE, 2^32)` to physical addresses:
```
   perm = PTE_P | PTE_W;
   size = ~0;
   size = size - KERNBASE + 1;
   size = ROUNDUP(size, PGSIZE);
   boot_map_region(kern_pgdir, KERNBASE, size, 0, perm);
```

One of my concern is that before we finish mapping va above `KERNBASE`, is it possible that the initial 4MB mapping is not enough so that we can't access to more virtual memory ?

But seems 4MB is enough. After setting up all virtual memory, the va of the last allocated page is `0xf03be000`, which doesn't reach `0xf0000000 + 4MB = 0xf0400000`. That's why only 4MB is enough.

## Questions

Only one question is interesting:
> Revisit the page table setup in kern/entry.S and kern/entrypgdir.c. Immediately after we turn on paging, EIP is still a low number (a little over 1MB). At what point do we transition to running at an EIP above KERNBASE? What makes it possible for us to continue executing at a low EIP between when we enable paging and when we begin running at an EIP above KERNBASE? Why is this transition necessary?

See `entry.S`, it's true that some instructions run with a low EIP:
```
   # Now paging is enabled, but we're still running at a low EIP
   # (why is this okay?).  Jump up above KERNBASE before entering
   # C code.
   mov   $relocated, %eax
   jmp   *%eax
```
After `jump *%eax`, we transition to running at an EIP above KERNBASE.
Why is OK to run at low address for a short time ? It's because the temporary page table also set mapping from `[0, 4MB] to [0, 4MB]`, see `entrypgdir.c`:
```
__attribute__((__aligned__(PGSIZE)))
pde_t entry_pgdir[NPDENTRIES] = {
   // Map VA's [0, 4MB) to PA's [0, 4MB)
   [0]
      = ((uintptr_t)entry_pgtable - KERNBASE) + PTE_P,
   // Map VA's [KERNBASE, KERNBASE+4MB) to PA's [0, 4MB)
   [KERNBASE>>PDXSHIFT]
      = ((uintptr_t)entry_pgtable - KERNBASE) + PTE_P + PTE_W
};
```
This transition is necessary because the code which runs later is compiled and linked at the address above KERNBASE.

## Challenges

// TODO
