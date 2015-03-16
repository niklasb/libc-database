## Building a libc offset database

Fetch all the configured libc versions and extract the symbol offset

    $ ./get

Find all the libc's in the database that have a given name at the given address
(only the last 12 bits are checked, because randomization usually works on page
size level)

    $ ./find printf 260
    archive-eglibc (id 2.15-0ubuntu10_amd64)
    archive-glibc (id 2.19-10ubuntu2_i386)
    archive-glibc (id 2.19-10ubuntu2_i386)

Find a libc from the leaked return address into __libc_start_main.

    $ ./find __libc_start_main_ret a83
    ubuntu-trusty-i386 (id 2.19-0ubuntu6.6_i386)
    archive-eglibc (id 2.19-0ubuntu6_i386)
    ubuntu-utopic-i386 (id 2.19-10ubuntu2.3_i386)
    archive-glibc (id 2.19-10ubuntu2_i386)
    archive-glibc (id 2.19-15ubuntu2_i386)

Dump some useful offsets, given a libc ID:

    $ ./dump 2.19-0ubuntu6.6_i386
    offset___libc_start_main_ret = 0x19a83
    offset_system = 0x00040190
    offset_dup2 = 0x000db590
    offset_recv = 0x000ed2d0
    offset_str_bin_sh = 0x160a24
