#!/usr/bin/env python3
"""Which interpreter runs what, in one place.

TWO DIFFERENT ANSWERS, and the reason is measured rather than assumed. The
numbers are in docs/speed.md:

  A GATE drives the 6809 emulator, which is Python interpreting an
  instruction at a time. PyPy runs it between four and eight times faster
  than CPython with byte-identical output - `test_summing_new` went from
  279.7 s to 35.0 s - so every gate and the differential harness get PyPy
  when it is installed.

  THE ASSEMBLER does not gain: 2.20 s under CPython against 1.85 s under
  PyPy, because the JIT never warms up inside a run that short. It stays on
  the interpreter that started the process, which is also the one the rest
  of the tooling uses.

If PyPy is not installed, gate_python() hands back the running interpreter and
everything still works, slower. Nothing in the emulator or the gates was
changed to run under PyPy; it took them as they were.
"""
import os
import shutil
import sys

# The names Homebrew and the distributions use, newest first.
PYPY_NAMES = ("pypy3.11", "pypy3.10", "pypy3", "pypy")


def gate_python():
    """The fastest interpreter that can run the emulator."""
    if os.environ.get("HP8904A_NO_PYPY"):
        return sys.executable
    for name in PYPY_NAMES:
        found = shutil.which(name)
        if found:
            return found
    return sys.executable


def build_python():
    """The interpreter for the assembler, which gains nothing from PyPy."""
    return sys.executable


def build_dir(default):
    """Where a build writes, and where the gates read it back.

    HP8904A_BUILD NAMES A DIFFERENT DIRECTORY. Every assemble writes the same
    five images, the same listings and code_bytes.json, and every gate reads
    them - so two builds at once corrupt each other's output and a build
    during a gate corrupts the gate, which is why only one build may run at
    a time.

    A single global directory makes that hazard unavoidable even with one
    checkout: an editor, a checker and a gate can all be in it at once. Reading the
    path from the environment costs nothing, keeps the default exactly where
    it was, and is the one change that would let several ports run at the same
    time - each checkout exports its own and nothing they do can meet.
    """
    # AND IT PUTS THE ANSWER BACK IN THE ENVIRONMENT, so the process says out
    # loud which directory it is using. A build lock that reads each live
    # build's HP8904A_BUILD out of `ps -E` treats one it cannot determine
    # as colliding with everything - which is the right default for a lock,
    # and which meant a run started in the MAIN tree, where nobody exports the
    # variable because the default is already correct, locked every worktree
    # out. Measured: a second checkout was blocked for about fifteen minutes
    # by a differential sweep in the main tree. Naming the default costs nothing and makes
    # the lock as precise as it was designed to be.
    chosen = os.environ.get("HP8904A_BUILD") or default
    os.environ["HP8904A_BUILD"] = chosen
    return chosen
