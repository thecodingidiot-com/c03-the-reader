# c03-the-reader

Companion repository for **c03 — The Reader** at
[thecodingidiot.com](https://thecodingidiot.com).

---

## Follow my journey

Working through c03 alongside the implementation pages? Build `tci_getline`
and `tciu_split` step by step, then run the tester.

Clone this repository and copy `test.sh` into your working directory:

```bash
git clone https://github.com/thecodingidiot-com/c03-the-reader.git
cp c03-the-reader/test.sh ~/c03-practice/
cd ~/c03-practice
make re
bash test.sh
```

All tests must pass before the chapter is complete.

---

## Follow your journey

Building `tci_getline` and `tciu_split` independently? Here is the full
project brief.

**libtci:** add `tci_getline` to the library from c02.

```c
char    *tci_getline(int fd);
```

Returns the next line from `fd`, including the trailing `'\n'` if present.
Returns NULL at EOF or on a read error. Must work for any compile-time
`BUFFER_SIZE ≥ 1`. Supports multiple file descriptors open simultaneously,
each with its own saved state.

Compile with: `gcc -Wall -Wextra -g -std=c99 -D BUFFER_SIZE=32`

**libtciutil:** introduce a second library — `libtciutil.a` / `libtciutil.h` — and add
`tciu_split` as its first function.

```c
char    **tciu_split(char const *s, char sep);
```

Returns a NULL-terminated array of strings split on `sep`. NULL input returns
NULL. Consecutive separators produce no empty strings. The caller owns the
returned array and all strings in it.

Link order: `gcc ... -L. -ltciutil -ltci -I.`

Build and test your own version first. Use `solution/` to compare once you
are done, not before.

---

## What the tester checks

**tci_getline suite** (run with BUFFER_SIZE = 1, 7, 32, 4096):

- Short file (all lines with `\n`)
- Long file (lines longer than BUFFER_SIZE)
- File with no trailing newline
- Empty file
- Invalid file descriptor

**Multiple file descriptors:**

- Two files read interleaved; each fd must maintain its own state

**Valgrind:**

- No memory leaks reading a file to completion
- No memory leaks with a no-trailing-newline file

**tciu_split suite:**

- Basic split, single field, custom delimiter
- Consecutive separators, leading/trailing separators, separator-only string
- Empty string, NULL input, fields with spaces
- Real-world quiz line format

---

## License

GPLv2. See [LICENSE](LICENSE).
