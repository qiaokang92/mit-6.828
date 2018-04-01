# Lab 1: Booting a PC

## Environment setup

MIT requires to build a patched QEMU, see your needed
tools from this [link](https://pdos.csail.mit.edu/6.828/2016/tools.html)

Seems the git repo provided by MIT is not working, you can use this one instead.
```
git clone https://github.com/geofft/qemu.git -b 6.828-2.3.0
```

How to build QEMU from source code? see [tools page](https://pdos.csail.mit.edu/6.828/2016/tools.html).

## Part 1 PC bootstrap

### Getting Started

MIT suggests a book: PC assembly language to learn x86 assembly language.
[The Brennan's Guide to Inline Assembly](http://www.delorie.com/djgpp/doc/brennan/brennan_att_inline_djgpp.html) 
teaches you how to convert asm syntax between intel syntax and AT&T syntax.

**Exercies 1**: read the material above.

If you need official reference about x86 instructions, see:
1. the short one: 80386 Programmer's Reference Manual
2. the greatest one: IA-32 Intel Architecture Software Developer's Manuals

Now we download the original JOS code, build and run in qemu
```
git clone https://pdos.csail.mit.edu/6.828/2016/jos.git lab
cd lab
make
make qemu-nox
```
Then you can play with the `K>` console.

### A PC's Physical Memory

A 32-bit PC's physical address look likes:
```
+------------------+  <- 0xFFFFFFFF (4GB)
|      32-bit      |
|  memory mapped   |
|     devices      |
|                  |
/\/\/\/\/\/\/\/\/\/\

/\/\/\/\/\/\/\/\/\/\
|                  |
|      Unused      |
|                  |
+------------------+  <- depends on amount of RAM
|                  |
|                  |
| Extended Memory  |
|                  |
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

The 640KB area marked "Low Memory" was the only random-access memory (RAM) that an early PC could use.
The 384KB area memory from 0x000A0000 to 0x00100000 was preserved for special uses like BIOS and video buffer.

When Intel supports 4G memory, there is a "hole" in physical memory, that is the 384KB from 0x000A0000 to 0x00100000, which deivides the whole memory into **Low Memory** and **Extened Memory**.

The very top part of 4G memory is commonly presevered by BIOS for PCI devices.

Note: JOS only uses the first 256MB of a PC's physical memory.

### Play the BIOS

Now let's play with the BIOS by running:
```
# in one terminal
make qemu-nox-gdb
# in another terminal
make gdb
```

The first instruction the CPU executes is
```
[f000:fff0] 0xffff0: ljmp  $0xf000,$0xe05b
```
Which means:
- PC starts running at `0xffff0`
- PC wants to jump to `0xfe0b5`

Note: in real mode, physical address = 16 * segment + offset.

**Exercise 2** asks to use `si` to see what the BIOS is doing.

BIOS should:
1. set up an interrupt descriptor table.
2. initialize various devices such as the VGA display.
3. initialize PCI bus and all important devices.
4. find the bootable disk, read the bootloader to memory.
5. transfer control to the bootloader.

## Part 2: The Boot Loader

A Disk has many many **sectors**, each 512 bytes. If the disk is bootable, the first sector is called **boot sector**.

BIOS will load the content of boot sector into memory at physical addresses 0x7c00 through 0x7dff, and jmp to CS:IP to 0000:7c00, passing control to the boot loader.

The boot loader code is `boot/boot.S` and `boot/main.c`. Now you should go through the code and understand what the code is doing.

- First, it switches to 32-bit protected mode, then CPU can access memory over 1MB. In protected mode, offset is 32-bit long instead of 16-bit.
- Second, it reads the kernel from HD by accessing the ID disk.

Some tips: you can read `obj/boot/boot.asm` to better understand `boot/boot.asm`, as this file makes it easy to see exactly where in physical memory all of the boot loader's code reside

Now answer some questions of **Exercise 3**:
1. At what point does the processor start executing 32-bit code? What exactly causes the switch from 16- to 32-bit mode?
2. What is the last instruction of the boot loader executed, and what is the first instruction of the kernel it just loaded?
3. Where is the first instruction of the kernel?
4. How does the boot loader decide how many sectors it must read in order to fetch the entire kernel from disk? Where does it find this information?

Followings are my answers:

1. `0x7c2d ljmp    $PROT_MODE_CSEG, $protcseg`
2. last of boot loader: `7d6b:   ff 15 18 00 01 00       call   *0x10018`; first of kernel: `f010000c:   66 c7 05 72 04 00 00    movw   $0x1234,0x472`
3. see 2
4. It is decided by the number of ELF program headers, which can be read from ELF header. See `boot/main.c:51`

**Exercise 4** suggests reading some C programming language materials, like _The C Programming Language_. They highly recommend reading 5.1 (Pointers and Addresses) through 5.5 (Character Pointers and Functions) in this book.

**Exercise 5** is really interesting:

> Trace through the first few instructions of the boot loader again and identify the first instruction that would "break" or otherwise do the wrong thing if you were to get the boot loader's link address wrong. Then change the link address in boot/Makefrag to something wrong, run make clean, recompile the lab with make, and trace into the boot loader again to see what happens. Don't forget to change the link address back and make clean again afterward!

If we change the boot loader's link address to a wrong value, the `jmp` addresses in boot loader's code will be changed accordingly. However, BIOS always loads the bootloader into a fixed address, i.e., `0x7c00`. So once `jmp` happens, bootloader will jump to a wrong address.

**Exercise 6**

> Reset the machine (exit QEMU/GDB and start them again). Examine the 8 words of memory at 0x00100000 at the point the BIOS enters the boot loader, and then again at the point the boot loader enters the kernel. Why are they different? What is there at the second breakpoint? (You do not really need to use QEMU to answer this question. Just think.)

1. Breakpoint 1: nothing changed.
2. Breakpoint 2: since bootloader has loaded kernel into `0x100000`, you will be able to find kernel code there.

Conclude what boot loader does:
1. The boot loader starts running at `0x7c00`
2. The boot loader loads kernel to `0x100000`, and transfers control to kernel at the ELF entry point.
3. The boot loader uses complete physical addresses, no virtual memory at all.

## The Kernel

Now we talk about the initial memory mapping that JOS kernel does.
See the figure below:

![](http://p6hn151zy.bkt.clouddn.com/kernel_mapping.jpg)

Basically, JOS maps 0xf0000000 ~ 0xffffffff to the first 256 physical memory.
That's why JOS can only uses the first 256 MB memory.
The kernel starts running at `0x100000`, it then maps VA `0xf0100000` to MA `0x100000` to enable virtual memory support.

**Exercise 7** is interesting as well

> (1) Use QEMU and GDB to trace into the JOS kernel and stop at the movl %eax, %cr0. Examine memory at 0x00100000 and at 0xf0100000. Now, single step over that instruction using the stepi GDB command. Again, examine memory at 0x00100000 and at 0xf0100000. Make sure you understand what just happened.

Simple. After setting up virtual memory, you can see identical bytes at `0x100000` and at `0xf0100000`.

> (2) What is the first instruction after the new mapping is established that would fail to work properly if the mapping weren't in place? Comment out the movl %eax, %cr0 in kern/entry.S, trace into it, and see if you were right.

This is a good question. Since `movl %eax, %cr0` was commented, MMU was not enabled. So after we jump to `relocated`, the CPU tries to execute an instruction at `0xf010002c`, which is fatal error. The VM will be dumped and killed by QEMU.

### Formatted Printing

**Exercise 8** requests you to finish writing `cpintf` to support printing (unsigned) octal numbers. Just have a look at how to print hex numbers and things will be quite easy.

```
      // (unsigned) octal
      case 'o':
         putch('0', putdat);
         num = getuint(&ap, lflag);
         base = 8;
         goto number;
```

There are a couple of questions:

(1) Explain the interface between printf.c and console.c. Specifically, what function does console.c export? How is this function used by printf.c?

Basically, `console.c` exports `cputchar()` and `getchar()`, which are used by `printf.c` to print a character or get a character from console.

(2) Explain the following from console.c:
```
      if (crt_pos >= CRT_SIZE) {
               int i;
               memmove(crt_buf, crt_buf + CRT_COLS, (CRT_SIZE - CRT_COLS) * sizeof(uint16_t));
               for (i = CRT_SIZE - CRT_COLS; i < CRT_SIZE; i++)
                       crt_buf[i] = 0x0700 | ' ';
               crt_pos -= CRT_COLS;
       }
```

If the current screen is full(`crt_pos >= CRT_SIZE`), we should move all of things back by one line. The first line will be flushed so we don't need to move them.
Then we fills out the new line with blanks, and move the cursor to the beginning of the line.

(3) For the following questions you might wish to consult the notes for Lecture 2. These notes cover GCC's calling convention on the x86. Trace the execution of the following code step-by-step.
    (a) In the call to cprintf(), to what does fmt point? To what does ap point?
    (b) List (in order of execution) each call to cons_putc, va_arg, and vcprintf. For cons_putc, list its argument as well. For va_arg, list what ap points to before and after the call. For vcprintf list the values of its two arguments.
```
int x = 1, y = 3, z = 4;
cprintf("x %d, y %x, z %d\n", x, y, z);
```

For (a), fmt points to the string of `"x %d, y %x, z %d\n"`, while ap points to argument list (i.e. the first argument).

For (b), ok, I am too lazy to finish this question. Just paste the answer here:

(4) Run the following code
```
    unsigned int i = 0x00646c72;
    cprintf("H%x Wo%s", 57616, &i);
```
What is the output? Explain how this output is arrived at in the step-by-step manner of the previous exercise. Here's an ASCII table that maps bytes to characters.

The output depends on that fact that the x86 is little-endian. If the x86 were instead big-endian what would you set i to in order to yield the same output? Would you need to change 57616 to a different value?

**My answer**:
`%x` prints `57616` to hex format, i.e., `0xe110`. `i` will be treated as a string, i.e. `rld\0x00`. So the complete output should be: `He110 World`.

For the next questions, even if big-endian is applied, we don't need to change `57616`. Instead, `i` should be changed to `0x726c6400`

(5) In the following code, what is going to be printed after 'y='? (note: the answer is not a specific value.) Why does this happen?
```
    cprintf("x=%d y=%d", 3);
```

This value is undefined. The stack looks like:
```
=== unknown values ===
=== last arg: 3 pushed ===
=== first arg: string pushed ===
=== return addr ===
=== pushed EBP ===
```

So this value is unknown.

(6) Let's say that GCC changed its calling convention so that it pushed arguments on the stack in declaration order, so that the last argument is pushed last. How would you have to change cprintf or its interface so that it would still be possible to pass it a variable number of arguments?

// TODO

Challenge

// TODO

### The Stack

This section talks about the stack.

**Exercise 9**. Determine where the kernel initializes its stack, and exactly where in memory its stack is located. How does the kernel reserve space for its stack? And at which "end" of this reserved area is the stack pointer initialized to point to?

See `entry.S`: `mov $0xf010f000,%esp`, seems the top of the stack is `0xf010f000`.

**Exercise 10** is about C calling convention. I don't think it's necessary.

**Exercise 11** asks you to implement a basic backtrace, this is my code:
```
int mon_backtrace()
{
   // Your code here.
   uint32_t *ebp, *i, *eip;
   int j;
   ebp = (uint32_t *)read_ebp();
   cprintf("Stack backtrace:\n");
   while(ebp) {
      eip = ebp + 1;
      cprintf("  ebp %08x eip %08x args", ebp, *eip);
      //for (i = eip + 1; i <= (uint32_t *)(*ebp); i --) {
      for (j = 2; j < 7; j ++) {
         cprintf(" %08x", ebp[j]);
      }
      cprintf("\n");
      ebp = (uint32_t *)(*ebp);
   }
   return 0;
}
```

NOTE: you should use `while(ebp)` instead of `while(*ebp)`. If you use the latter one, there will be one missing line in your output.

**Exercise 12** asks you to implement a more complete `bt`, which prints line numbers, function names, source files, etc...

First, we need to complete `debuginfo_eip`

```
   stab_binsearch(stabs, &lline, &rline, N_SLINE, addr);
   if (lline > rline) {
      return -1;
   }
```

We call `stab_binsearch` to locate the line number for the eip.

Then we need to call `debuginfo_eip` in `mon_backtrace` function
```
      /* Exercise 12 */
      debuginfo_eip(*eip, &info);
      cprintf("\n     %s:%d: %.*s+%d\n",
              info.eip_file,
              info.eip_line,
              info.eip_fn_namelen,
              info.eip_fn_name,
              *eip - info.eip_fn_addr);
```

This completes Lab 1.
