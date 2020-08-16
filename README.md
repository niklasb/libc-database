## Building a libc offset database

Fetch all the configured libc versions and extract the symbol offsets.
It will not download anything twice, so you can also use it to update your
database:

    $ ./get

You can also add a custom libc to your database.

    $ ./add /usr/lib/libc-2.21.so

Find all the libc's in the database that have the given names at the given
addresses. Only the last 12 bits are checked, because randomization usually
works on page size level.

    $ ./find printf 260 puts f30
    archive-glibc (id libc6_2.19-10ubuntu2_i386)

Find a libc from the leaked return address into `__libc_start_main`.

    $ ./find __libc_start_main_ret a83
    ubuntu-trusty-i386-libc6 (id libc6_2.19-0ubuntu6.6_i386)
    archive-eglibc (id libc6_2.19-0ubuntu6_i386)
    ubuntu-utopic-i386-libc6 (id libc6_2.19-10ubuntu2.3_i386)
    archive-glibc (id libc6_2.19-10ubuntu2_i386)
    archive-glibc (id libc6_2.19-15ubuntu2_i386)

Dump some useful offsets, given a libc ID. You can also provide your own names
to dump.

    $ ./dump libc6_2.19-0ubuntu6.6_i386
    offset___libc_start_main_ret = 0x19a83
    offset_system = 0x00040190
    offset_dup2 = 0x000db590
    offset_recv = 0x000ed2d0
    offset_str_bin_sh = 0x160a24

Check whether a library is already in the database.

    $ ./identify /usr/lib/libc.so.6
    id local-f706181f06104ef6c7008c066290ea47aa4a82c5

Or find a libc using a hash (currently BuildID, MD5, SHA1 and SHA256 is
implemented)

    $ ./identify bid=ebeabf5f7039f53748e996fc976b4da2d486a626
    id libc6_2.17-93ubuntu4_i386
    $ ./identify md5=af7c40da33c685d67cdb166bd6ab7ac0
    id libc6_2.17-93ubuntu4_i386
    $ ./identify sha1=9054f5cb7969056b6816b1e2572f2506370940c4
    id libc6_2.17-93ubuntu4_i386
    $ ./identify sha256=8dc102c06c50512d1e5142ce93a6faf4ec8b6f5d9e33d2e1b45311aef683d9b2
    id libc6_2.17-93ubuntu4_i386

Download the whole libs corresponding to a libc ID.

    $ ./download libc6_2.23-0ubuntu10_amd64
    Getting libc6_2.23-0ubuntu10_amd64
        -> Location: http://security.ubuntu.com/ubuntu/pool/main/g/glibc/libc6_2.23-0ubuntu10_amd64.deb
        -> Downloading package
        -> Extracting package
        -> Package saved to libs/libc6_2.23-0ubuntu10_amd64
    $ ls libs/libc6_2.23-0ubuntu10_amd64
    ld-2.23.so ... libc.so.6 ... libpthread.so.0 ...
