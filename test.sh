#!/bin/bash
# c03 — The Reader / test.sh
#
# Tests il_getline (idiotlib) and fg_split (forge).
# Copy this file into your working directory alongside libidiot.a,
# libforge.a, and all il_*.c / fg_*.c source files, then run:
#
#   bash test.sh

set -o pipefail

# ── colour ────────────────────────────────────────────────────────────────────

if [[ ! -t 1 ]]; then
    C_GREEN=""
    C_RED=""
    C_BOLD=""
    C_RESET=""
else
    C_GREEN="\033[0;32m"
    C_RED="\033[0;31m"
    C_BOLD="\033[1m"
    C_RESET="\033[0m"
fi

# ── state ─────────────────────────────────────────────────────────────────────

pass_count=0
fail_count=0
WORK_DIR=$(mktemp -d)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="${SCRIPT_DIR}/fixtures"

# ── cleanup ───────────────────────────────────────────────────────────────────

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# ── helpers ───────────────────────────────────────────────────────────────────

hr() {
    echo "────────────────────────────────────────────────────────────────"
}

banner() {
    hr
    echo "  c03 — The Reader / test.sh"
    hr
}

pass() {
    local label="$1"
    printf "  ${C_GREEN}PASS${C_RESET}  %s\n" "$label"
    pass_count=$((pass_count + 1))
}

fail() {
    local label="$1"
    printf "  ${C_RED}FAIL${C_RESET}  %s\n" "$label"
    fail_count=$((fail_count + 1))
}

check_output() {
    local label="$1"
    local got="$2"
    local expected="$3"
    if [[ "$got" == "$expected" ]]; then
        pass "$label"
    else
        fail "$label"
        printf "    expected: %s\n" "$(printf '%s' "$expected" | cat -v)"
        printf "    got:      %s\n" "$(printf '%s' "$got" | cat -v)"
    fi
}

# compare_files: run a command, diff its raw output against an expected file
# usage: compare_files label expected_file cmd [args...]
compare_files() {
    local label="$1"
    local expected_file="$2"
    shift 2
    "$@" > "${WORK_DIR}/got.txt" 2>/dev/null
    if diff -q "$expected_file" "${WORK_DIR}/got.txt" > /dev/null 2>&1; then
        pass "$label"
    else
        fail "$label"
        diff --unified=1 "$expected_file" "${WORK_DIR}/got.txt" | tail -n +4 | \
            head -10 | while IFS= read -r line; do printf "    %s\n" "$line"; done
    fi
}

# ── pre-flight ────────────────────────────────────────────────────────────────

preflight() {
    local ok=1
    for tool in gcc make valgrind; do
        if ! command -v "$tool" &>/dev/null; then
            echo "error: $tool is not installed" >&2
            ok=0
        fi
    done
    if [[ ! -f Makefile ]]; then
        echo "error: Makefile not found — run from your working directory" >&2
        ok=0
    fi
    if [[ ! -f libidiot.a ]]; then
        echo "error: libidiot.a not found — run 'make re' first" >&2
        ok=0
    fi
    if [[ ! -f libforge.a ]]; then
        echo "error: libforge.a not found — run 'make re' first" >&2
        ok=0
    fi
    if [[ ! -f il_getline.c ]]; then
        echo "error: il_getline.c not found in current directory" >&2
        ok=0
    fi
    if [[ ! -f fg_split.c ]]; then
        echo "error: fg_split.c not found in current directory" >&2
        ok=0
    fi
    if [[ ! -d "$FIXTURES" ]]; then
        echo "error: fixtures/ directory not found alongside test.sh" >&2
        ok=0
    fi
    if [[ $ok -eq 0 ]]; then
        exit 1
    fi
}

# ── il_getline runner ─────────────────────────────────────────────────────────
#
# Compiles il_getline.c fresh with a given BUFFER_SIZE, linking against
# libidiot.a for all dependencies. The fresh il_getline.o takes precedence
# over the one inside libidiot.a so the BUFFER_SIZE override works cleanly.

build_gl_runner() {
    local bs="$1"
    local out="${WORK_DIR}/gl_runner_bs${bs}"
    cat > "${WORK_DIR}/gl_runner.c" << 'RUNNER_EOF'
#include "idiotlib.h"
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>

int     main(int argc, char **argv)
{
    int     fd;
    char    *line;

    if (argc != 2)
        return (1);
    fd = open(argv[1], O_RDONLY);
    if (fd < 0)
        return (1);
    while ((line = il_getline(fd)) != NULL) {
        printf("%s", line);
        free(line);
    }
    close(fd);
    return (0);
}
RUNNER_EOF
    gcc -Wall -Wextra -g -std=c99 -D "BUFFER_SIZE=${bs}" \
        -o "$out" \
        "${WORK_DIR}/gl_runner.c" \
        il_getline.c \
        -L. -lidiot -I. 2>"${WORK_DIR}/build_err.txt"
    if [[ $? -ne 0 ]]; then
        echo "  build failed (BUFFER_SIZE=${bs}):" >&2
        cat "${WORK_DIR}/build_err.txt" >&2
        return 1
    fi
    echo "$out"
}

# ── multi-fd runner ───────────────────────────────────────────────────────────

build_multifd_runner() {
    local bs="$1"
    local out="${WORK_DIR}/gl_multifd_bs${bs}"
    cat > "${WORK_DIR}/gl_multifd.c" << 'RUNNER_EOF'
#include "idiotlib.h"
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>

int     main(int argc, char **argv)
{
    int     fd1;
    int     fd2;
    int     done1;
    int     done2;
    char    *line;

    if (argc != 3)
        return (1);
    fd1 = open(argv[1], O_RDONLY);
    fd2 = open(argv[2], O_RDONLY);
    if (fd1 < 0 || fd2 < 0)
        return (1);
    done1 = 0;
    done2 = 0;
    while (!done1 || !done2) {
        if (!done1) {
            line = il_getline(fd1);
            if (line) { printf("A:%s", line); free(line); }
            else done1 = 1;
        }
        if (!done2) {
            line = il_getline(fd2);
            if (line) { printf("B:%s", line); free(line); }
            else done2 = 1;
        }
    }
    close(fd1);
    close(fd2);
    return (0);
}
RUNNER_EOF
    gcc -Wall -Wextra -g -std=c99 -D "BUFFER_SIZE=${bs}" \
        -o "$out" \
        "${WORK_DIR}/gl_multifd.c" \
        il_getline.c \
        -L. -lidiot -I. 2>/dev/null
    echo "$out"
}

# ── fg_split runner ───────────────────────────────────────────────────────────

build_split_runner() {
    local out="${WORK_DIR}/split_runner"
    cat > "${WORK_DIR}/split_runner.c" << 'RUNNER_EOF'
#include "forge.h"
#include <stdio.h>
#include <stdlib.h>

int     main(int argc, char **argv)
{
    char    **words;
    int     i;
    char    sep;

    if (argc < 2) {
        /* NULL input test */
        words = fg_split(NULL, '|');
        if (!words)
            printf("(null)\n");
        return (0);
    }
    sep = (argc >= 3) ? argv[2][0] : '|';
    words = fg_split(argv[1], sep);
    if (!words) {
        printf("(null)\n");
        return (0);
    }
    i = 0;
    while (words[i]) {
        printf("[%s]\n", words[i]);
        free(words[i++]);
    }
    free(words);
    return (0);
}
RUNNER_EOF
    gcc -Wall -Wextra -g -std=c99 \
        -o "$out" \
        "${WORK_DIR}/split_runner.c" \
        fg_split.c \
        -L. -lforge -lidiot -I. 2>"${WORK_DIR}/build_err.txt"
    if [[ $? -ne 0 ]]; then
        echo "  build failed (fg_split runner):" >&2
        cat "${WORK_DIR}/build_err.txt" >&2
        return 1
    fi
    echo "$out"
}

# ── il_getline tests ──────────────────────────────────────────────────────────

run_getline_suite() {
    echo ""
    echo "${C_BOLD}  il_getline${C_RESET}"
    echo ""

    # build expected files once (they don't change across BUFFER_SIZE runs)
    cp "${FIXTURES}/short.txt"      "${WORK_DIR}/expected_short.txt"
    cp "${FIXTURES}/long.txt"       "${WORK_DIR}/expected_long.txt"
    cp "${FIXTURES}/no_newline.txt" "${WORK_DIR}/expected_nonl.txt"
    cp "${FIXTURES}/empty.txt"      "${WORK_DIR}/expected_empty.txt"

    local bs
    for bs in 1 7 32 4096; do
        local runner
        runner=$(build_gl_runner "$bs") || { fail "build BUFFER_SIZE=${bs}"; continue; }

        compare_files "short file       BUFFER_SIZE=${bs}" \
            "${WORK_DIR}/expected_short.txt" "$runner" "${FIXTURES}/short.txt"

        compare_files "long lines       BUFFER_SIZE=${bs}" \
            "${WORK_DIR}/expected_long.txt"  "$runner" "${FIXTURES}/long.txt"

        compare_files "no trailing \\n   BUFFER_SIZE=${bs}" \
            "${WORK_DIR}/expected_nonl.txt"  "$runner" "${FIXTURES}/no_newline.txt"

        compare_files "empty file       BUFFER_SIZE=${bs}" \
            "${WORK_DIR}/expected_empty.txt" "$runner" "${FIXTURES}/empty.txt"
    done

    # invalid fd — must return NULL (no output, exit 0)
    local runner
    runner=$(build_gl_runner 32) || return
    cat > "${WORK_DIR}/invalid_fd.c" << 'EOF'
#include "idiotlib.h"
#include <stdio.h>
int main(void)
{
    char *line = il_getline(-1);
    printf("%s", line ? line : "(null)");
    return 0;
}
EOF
    gcc -Wall -Wextra -g -std=c99 -D BUFFER_SIZE=32 \
        -o "${WORK_DIR}/invalid_fd" \
        "${WORK_DIR}/invalid_fd.c" \
        il_getline.c -L. -lidiot -I. 2>/dev/null
    local got
    got=$("${WORK_DIR}/invalid_fd")
    check_output "invalid fd (-1)" "$got" "(null)"
}

# ── multi-fd tests ────────────────────────────────────────────────────────────

run_multifd_suite() {
    echo ""
    echo "${C_BOLD}  il_getline — multiple file descriptors${C_RESET}"
    echo ""

    # build expected interleaved output file
    printf 'A:alpha\nB:delta\nA:bravo\nB:echo\nA:charlie\nB:foxtrot\n' \
        > "${WORK_DIR}/expected_multifd.txt"

    local bs
    for bs in 1 32; do
        local runner
        runner=$(build_multifd_runner "$bs") || { fail "build multi-fd BUFFER_SIZE=${bs}"; continue; }
        compare_files "interleaved reads BUFFER_SIZE=${bs}" \
            "${WORK_DIR}/expected_multifd.txt" \
            "$runner" "${FIXTURES}/fd_a.txt" "${FIXTURES}/fd_b.txt"
    done
}

# ── valgrind test ─────────────────────────────────────────────────────────────

run_valgrind_suite() {
    echo ""
    echo "${C_BOLD}  valgrind — memory leaks${C_RESET}"
    echo ""

    local runner
    runner=$(build_gl_runner 32) || return

    local vg_out
    vg_out=$(valgrind --leak-check=full --error-exitcode=1 \
        "$runner" "${FIXTURES}/short.txt" 2>&1)
    if [[ $? -eq 0 ]]; then
        pass "no leaks reading short.txt to completion"
    else
        fail "no leaks reading short.txt to completion"
        echo "$vg_out" | grep -E "definitely lost|indirectly lost|ERROR" | \
            while IFS= read -r line; do printf "    %s\n" "$line"; done
    fi

    vg_out=$(valgrind --leak-check=full --error-exitcode=1 \
        "$runner" "${FIXTURES}/no_newline.txt" 2>&1)
    if [[ $? -eq 0 ]]; then
        pass "no leaks reading no-trailing-newline file"
    else
        fail "no leaks reading no-trailing-newline file"
        echo "$vg_out" | grep -E "definitely lost|indirectly lost|ERROR" | \
            while IFS= read -r line; do printf "    %s\n" "$line"; done
    fi
}

# ── fg_split tests ────────────────────────────────────────────────────────────

run_split_suite() {
    echo ""
    echo "${C_BOLD}  fg_split${C_RESET}"
    echo ""

    local runner
    runner=$(build_split_runner) || return

    local got expected

    # basic split on |
    got=$("$runner" "one|two|three" "|")
    expected=$'[one]\n[two]\n[three]'
    check_output "basic |           \"one|two|three\"" "$got" "$expected"

    # single field
    got=$("$runner" "hello" "|")
    expected="[hello]"
    check_output "single field      \"hello\"" "$got" "$expected"

    # different delimiter
    got=$("$runner" "a:b:c" ":")
    expected=$'[a]\n[b]\n[c]'
    check_output "delimiter :       \"a:b:c\"" "$got" "$expected"

    # consecutive separators — no empty fields
    got=$("$runner" "one||two" "|")
    expected=$'[one]\n[two]'
    check_output "consecutive ||    \"one||two\"" "$got" "$expected"

    # leading separator — ignored
    got=$("$runner" "|one|two" "|")
    expected=$'[one]\n[two]'
    check_output "leading |         \"|one|two\"" "$got" "$expected"

    # trailing separator — ignored
    got=$("$runner" "one|two|" "|")
    expected=$'[one]\n[two]'
    check_output "trailing |        \"one|two|\"" "$got" "$expected"

    # separator-only string
    got=$("$runner" "|||" "|")
    expected=""
    check_output "separator only    \"|||\"" "$got" "$expected"

    # empty string
    got=$("$runner" "" "|")
    expected=""
    check_output "empty string      \"\"" "$got" "$expected"

    # NULL input
    got=$("$runner")
    expected="(null)"
    check_output "NULL input" "$got" "$expected"

    # fields with spaces
    got=$("$runner" "hello world|foo bar" "|")
    expected=$'[hello world]\n[foo bar]'
    check_output "fields with spaces" "$got" "$expected"

    # single-char fields
    got=$("$runner" "a|b|c|d" "|")
    expected=$'[a]\n[b]\n[c]\n[d]'
    check_output "single-char fields" "$got" "$expected"

    # real-world: quiz line format from the chapter
    got=$("$runner" "What is C?|A language|A compiler|A linker|An OS|1" "|")
    expected=$'[What is C?]\n[A language]\n[A compiler]\n[A linker]\n[An OS]\n[1]'
    check_output "quiz line format" "$got" "$expected"
}

# ── summary ───────────────────────────────────────────────────────────────────

summary() {
    local total=$((pass_count + fail_count))
    echo ""
    hr
    printf "  %d / %d tests passed\n" "$pass_count" "$total"
    hr
    echo ""
    if [[ $fail_count -gt 0 ]]; then
        exit 1
    fi
}

# ── main ──────────────────────────────────────────────────────────────────────

banner
preflight
run_getline_suite
run_multifd_suite
run_valgrind_suite
run_split_suite
summary
