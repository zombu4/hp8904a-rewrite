#!/usr/bin/env python3
"""Build all five images of the handwritten HP 8904A firmware.

    python3 hp8904a-rewrite/build.py

A2U12 and A2U13 are one program in two devices, and this tree rewrites both
together. Five images come out of it:

    a2u12         32,768 bytes at $8000, always mapped
    a2u13_page0   16,384 bytes at $4000, one of four banked pages
    a2u13_page1   ...
    a2u13_page2   ...
    a2u13_page3   ...

Each is assembled by BOTH lwasm (LWTOOLS) and this repository's own
asm6809.py, and they must agree byte for byte. Two independent
implementations agreeing is worth much more than trusting one, and the bar is
known to be reachable: they already agree on all 98,304 bytes of the five
STOCK images with no source changes.

It also tracks the byte budget from the first module rather than at the end.
The stock firmware's page split is HP's answer to a 1987 space problem, and
this rewrite treats where code lives as a decision made against the real
budget - which means knowing, at every step, how much room is left in each
image rather than discovering it when the last module does not fit.

An empty or over-size image is refused. The first version of this build
emitted a zero-byte file and printed sha256 e3b0c442 for it, which reads
exactly like a successful build.
"""

import hashlib
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "scripts"))
from fastpython import gate_python, build_dir            # noqa: E402

# WHERE THIS BUILD WRITES. scripts/fastpython.py explains why it is a
# variable and not a constant: one global directory that every build
# writes and every gate reads is the hazard of two builds at once.
# The default is exactly where it always was.
BUILD = build_dir(os.path.join(HERE, "build"))

# name -> (root source, load address, exact size the part must be, the
#          checksum the instrument's own ROM test requires of it)
#
# THE EXPECTED CHECKSUM IS NOT ZERO FOR EVERY IMAGE. rom_checksum ($DCA9,
# disassembled in firmware/a2u12.asm at file offsets 5ca9 and 5cd2) requires
# zero from A2U12 and THE PAGE'S OWN NUMBER from A2U13 page N: it stores each
# page's result at $2481+page with `STB A,X` at 5ce5 and compares it against
# $247F at 5ce7, and $247F holds the page index. Because the expected value
# encodes the slot, the instrument's test catches a page burnt into the wrong
# socket, and a test that expects zero everywhere cannot.
IMAGES = {
    "a2u12":       ("images/a2u12.s",       0x8000, 32768, 0),
    "a2u13_page0": ("images/a2u13_page0.s", 0x4000, 16384, 0),
    "a2u13_page1": ("images/a2u13_page1.s", 0x4000, 16384, 1),
    "a2u13_page2": ("images/a2u13_page2.s", 0x4000, 16384, 2),
    "a2u13_page3": ("images/a2u13_page3.s", 0x4000, 16384, 3),
}

# HOW FAR BELOW THE TOP OF ITS IMAGE THE COMPENSATION BYTE SITS. The same
# number is COMP_BYTE_BACK in hp8904a-rewrite/common/formats.inc, where
# service_diag.s reads it to tell the operator the byte's address, and the two
# have to agree or the Diagnostics screen names a byte that is not this one.
COMP_BYTE_BACK = 17


def rom_checksum(image):
    """What the instrument's own ROM test leaves in B for this image.

    rom_checksum ($DCA9) is six instructions per leg:

        LDX #span-1 / CLRB / LEAX $1,X / ADCB ,X / CMPX #span-end / BNE

    and CMPX WRITES THE CARRY. The carry each ADCB consumes is therefore the
    borrow the previous compare left - 1 for as long as X is below the limit -
    and never the carry out of the previous addition. CLRB clears the carry,
    so the first byte adds with none in and every byte after it adds with one.
    In plain arithmetic the answer is (the sum of every byte, minus one) mod
    256, which is why the compensation byte can be calculated rather than
    searched for.
    """
    total, carry_in = 0, 0
    for byte in image:
        total = (total + byte + carry_in) & 0xFF
        carry_in = 1                    # the borrow the CMPX at the foot of
                                        # the loop leaves, every time round
                                        # but the last
    return total

os.makedirs(BUILD, exist_ok=True)
failures = []


def check(name, condition, detail=""):
    if condition:
        print(f"ok   {name}")
    else:
        print(f"FAIL {name}")
        if detail:
            print(f"       {detail}")
        failures.append(name)


total_written = 0

def emitted_bytes(path, upper_bound):
    """Bytes the source actually emitted, with padding runs discounted.

    A2U12 pads with `fill $FF` from the end of its code up to the ABI jump
    table at $F000, and that fill was being counted as code - which is how
    this build reported "31% of the firmware" when the honest figure was
    about 7%. Padding is not progress, and a measure that counts it flatters
    the work in exactly the place where flattering it is most misleading.

    Any run of 16 or more identical $FF bytes is treated as padding. Sixteen
    because no real instruction sequence or string in this firmware is that
    long a run of $FF, and a shorter threshold would start discounting data.
    A table of genuine $FF bytes longer than that would be undercounted, and
    if one is ever added this is where to say so.
    """
    data = open(path, "rb").read()[:upper_bound]
    padding, run = 0, 0
    for byte in data:
        if byte == 0xFF:
            run += 1
        else:
            if run >= 16:
                padding += run
            run = 0
    if run >= 16:
        padding += run
    return len(data) - padding


total_budget = 0
STOCK_BYTES = 98304      # the stock A2U12 plus A2U13's four pages
code_sizes = {}

code_bytes_written = {}

for name, (source, origin, target, expected) in IMAGES.items():
    path = os.path.join(HERE, source)
    lw = os.path.join(BUILD, f"{name}_lwasm.bin")
    own = os.path.join(BUILD, f"{name}_asm6809.bin")

    result = subprocess.run(["lwasm", "--raw", f"--output={lw}", path],
                            capture_output=True, text=True)
    if os.path.exists(lw):
        code_sizes[name] = os.path.getsize(lw)
    if result.returncode != 0:
        check(f"{name}: lwasm assembles it", False,
              (result.stdout + result.stderr).strip()[:300])
        continue

    # Place the CPU vector table. lwasm --raw concatenates ORG sections
    # rather than producing a sparse image, so a table written with
    # `org $FFF0` in the source would land right after the code instead of
    # where the CPU fetches it. The build lays the image out and puts the
    # vectors at the top, taking each handler's address from the assembler's
    # own symbol table so none of them is a number typed twice.
    def balance_checksum(raw_path):
        """Give the image the compensation byte its own self-test requires.

        WHAT THE TEST REQUIRES. rom_checksum ($DCA9) leaves the image's plain
        byte sum LESS ONE in B - see rom_checksum() above for why - and then
        demands zero of A2U12 and its own page number of A2U13 page N. So the
        PLAIN BYTE SUM this build has to produce is 1 for A2U12 and N+1 for
        page N, and one byte of the image is chosen to make that true. The
        stock images already are: a2u12.bin sums to 1 and pages 0 to 3 sum to
        1, 2, 3 and 4.

        CALCULATED, NOT SEARCHED. A plain byte sum is linear in every byte, so
        the compensation byte is just (what the sum must be) minus (the sum of
        everything else), modulo 256 - one subtraction rather than up to 256
        trial sums over 32 KB. It used to be searched because the model was a
        carry-chained sum, which is not linear and not what the instrument
        computes. The answer is still PROVED by running the instrument's own
        function over the finished image rather than trusted to the algebra.

        WHERE IT GOES: COMP_BYTE_BACK below the top of the image, which is
        $FFEF for A2U12 - immediately under the CPU vector table, the last
        byte that is neither code nor a vector - and $7FEF for a page. That
        spot has to be padding, and this refuses to write it if it is not: a
        page or A2U12 that ever grows into it fails the build here instead of
        losing an instruction to the checksum.
        """
        image = bytearray(open(raw_path, "rb").read())
        if len(image) != target:
            return
        spot = target - COMP_BYTE_BACK

        if image[spot] != 0xFF:
            check(f"{name}: the compensation byte's spot is free", False,
                  f"${origin + spot:04X} already holds "
                  f"${image[spot]:02X}, so this image's code or data has "
                  f"grown into the byte the checksum needs. Writing here "
                  f"would change an instruction. Move the code, or move the "
                  f"spot - and COMP_BYTE_BACK in common/formats.inc with it.")
            return

        want = (expected + 1) & 0xFF        # the plain byte sum the image
                                            # needs, the checksum being that
                                            # sum less one
        image[spot] = 0
        byte = (want - sum(image)) & 0xFF
        image[spot] = byte

        got = rom_checksum(image)
        if got != expected:
            check(f"{name}: the compensation byte satisfies the ROM test",
                  False,
                  f"placing ${byte:02X} at ${origin + spot:04X} leaves the "
                  f"instrument's checksum at ${got:02X}, not ${expected:02X}")
            return

        with open(raw_path, "wb") as handle:
            handle.write(bytes(image))
        print(f"     {name:12} checksum byte ${byte:02X} at "
              f"${origin + spot:04X}: plain byte sum ${sum(image) & 0xFF:02X}, "
              f"so rom_checksum ($DCA9) gets ${got:02X} - which is what it "
              f"requires of this image")

    def pad_to_part(raw_path):
        """A ROM image is the size of the part, not the size of the code.

        The four A2U13 pages were being left at whatever the code came to -
        523 bytes, 446 bytes - so concatenating them for the emulator put
        page 1 at offset 523 instead of 16384, and every paged call went
        somewhere else entirely. An EPROM does not have a short version.
        """
        code = open(raw_path, "rb").read()
        if len(code) >= target:
            return
        image = bytearray(b"\xFF" * target)
        image[0:len(code)] = code
        with open(raw_path, "wb") as handle:
            handle.write(bytes(image))

    def lay_out(raw_path, symbols):
        """Pad to the part's size and place the vectors, for either build."""
        code = open(raw_path, "rb").read()
        if len(code) > target:
            return 0
        image = bytearray(b"\xFF" * target)
        image[0:len(code)] = code
        # $FFF0 upward: reserved, SWI3, SWI2, FIRQ, IRQ, SWI, NMI, RESET
        vectors = ["reset_entry", "reset_entry", "reset_entry",
                   "firq_handler", "irq_handler", "reset_entry",
                   "nmi_handler", "reset_entry"]
        placed = 0
        for index, handler in enumerate(vectors):
            where = symbols.get(handler)
            if where is None:
                continue
            offset = target - 16 + index * 2
            image[offset] = (where >> 8) & 0xFF
            image[offset + 1] = where & 0xFF
            placed += 1
        with open(raw_path, "wb") as handle:
            handle.write(bytes(image))
        return placed

    # A LISTING FOR EVERY IMAGE, not only A2U12. A2U12's has always been made
    # because the vector table is laid out from its symbols; the paged images
    # had none, so a test that wanted to call one of their routines had to
    # run lwasm itself. They cost nothing - the assembler is being run either
    # way - and emulator/tests/test_digital_pack.py reads page 2's.
    listing = lw + ".lst"
    subprocess.run(["lwasm", "--raw", f"--output={lw}",
                    f"--list={listing}", path],
                   capture_output=True, text=True)

    if name == "a2u12":
        symbols = {}
        if os.path.exists(listing):
            for line in open(listing):
                found = re.match(r"^([0-9A-F]{4})\s+\S*\s+\([^)]*\):\d+\s+"
                                 r"(\w+)\s*$", line)
                if found:
                    symbols.setdefault(found.group(2),
                                       int(found.group(1), 16))
        placed = lay_out(lw, symbols)
        # AND ALL EIGHT, OR THE BUILD STOPS. lay_out skips a handler whose
        # symbol it cannot find, and this only PRINTED the count - so renaming
        # or losing reset_entry would have left $FFFF in the RESET vector, said
        # "7 of 8" in passing, and gone on to write the image. $FFFF is the
        # last two bytes of the part, and a processor that fetches its reset
        # vector from there runs into the vector table itself.
        #
        # Eight is right for A2U12 specifically, which is the only image this
        # branch reaches: the four handlers live here and the four unused slots
        # are deliberately pointed at reset_entry too.
        if placed != 8:
            raise SystemExit(
                f"build.py: {placed} of 8 CPU vectors placed for {name}. "
                "A vector left unwritten is $FFFF, and the RESET vector is "
                "not a byte to guess at - check that reset_entry, "
                "irq_handler, firq_handler and nmi_handler are all still "
                "defined and exported in the listing.")
        balance_checksum(lw)
        print(f"     {name:12} {placed} of 8 CPU vectors placed; unused ones "
              f"point at reset, so a spurious interrupt restarts rather than "
              f"running into whatever is there")

    if name != "a2u12":
        pad_to_part(lw)
        # AND ITS OWN COMPENSATION BYTE. Only A2U12 got one, so the
        # Diagnostics "ROM Checksum - both devices" screen could check one of
        # the two devices; each page carries one now, balanced to give its own
        # page number, which is what the power-on test and the Diagnostics
        # screen both require of it.
        # Placed after the padding, because the padding is part of the sum.
        balance_checksum(lw)

    size = os.path.getsize(lw)
    written_code = emitted_bytes(lw, code_sizes.get(name, size))
    total_written += written_code
    code_bytes_written[name] = written_code
    total_budget += target
    room = target - size
    # CODE bytes, never image size. An image padded to its part size is
    # 100% full of nothing, and reporting that as progress is how this build
    # once announced "31% of the firmware" when the honest figure was about
    # 7%. The padding is printed too, so the difference is visible rather
    # than merely excluded.
    padding = size - written_code
    print(f"     {name:12} {written_code:6} bytes of code"
          f" + {padding:6} padding = {size:6} of {target}"
          f"   ({written_code * 100.0 / target:5.1f}% code)")

    check(f"{name}: fits in its part", size <= target,
          f"{-room} bytes over. This image cannot be burnt to its device.")

    # asm6809.py refuses a source with no instructions, which is correct of
    # it. While a module is still only equates, that is expected and is
    # reported rather than counted as a failure.
    mine = subprocess.run([sys.executable,
                           os.path.join(ROOT, "firmware", "asm6809.py"),
                           path, "-o", own],
                          capture_output=True, text=True)
    if "nothing was assembled" in (mine.stdout + mine.stderr):
        continue
    if mine.returncode != 0:
        check(f"{name}: asm6809.py assembles it", False,
              (mine.stdout + mine.stderr).strip()[:300])
        continue
    if name != "a2u12" and os.path.exists(own):
        pad_to_part(own)            # the same layout, or the comparison is
        balance_checksum(own)       # between a finished image and a bare
                                    # code block and proves nothing - and the
                                    # compensation byte is part of the layout
                                    # now that every page carries one
    if name == "a2u12" and os.path.exists(own):
        # The same layout, or the comparison is between a finished image and
        # a bare code block and says nothing about whether the assemblers
        # agree.
        lay_out(own, symbols)
        balance_checksum(own)   # the same transformation, or the comparison
                                # is between a finished image and one that is
                                # a byte short of finished
    a, b = open(lw, "rb").read(), open(own, "rb").read()
    differ = sum(1 for x, y in zip(a, b) if x != y) + abs(len(a) - len(b))
    check(f"{name}: both assemblers agree byte for byte", differ == 0,
          f"{differ} byte(s) differ between lwasm and asm6809.py")

# The stock pair is 98,304 bytes and essentially all of it is code and data,
# so it is the only honest denominator available. It is a rough yardstick and
# is labelled as one: a rewrite that does the same job in fewer bytes is not
# 60% finished, and this figure must never be quoted as a completion
# percentage. What "finished" means is settled by the gates, not by a size.
# ONE MEASUREMENT, ONE SOURCE. test_no_stubs prints the code-byte figure that
# the owner's rules name as how "100% complete" is measured, and it was reading
# build/*.map - a file this build does not write. It found none, summed
# nothing, and printed "0 TOTAL" beside the words "the stock pair is 98,304
# bytes", which is the exact shape of the defect that rule exists to prevent:
# a figure that flatters or misleads because nobody checked what it counted.
#
# The build already knows the number. It writes it here and the gate reads it,
# so there is one place it can be wrong.
json.dump({"per_image": code_bytes_written, "total": total_written},
          open(os.path.join(BUILD, "code_bytes.json"), "w"), indent=1)

print(f"\n     {total_written} bytes of code across five images"
      f" ({total_written * 100.0 / STOCK_BYTES:.1f}% of the stock pair's"
      f" {STOCK_BYTES:,} bytes, as a size comparison and nothing more)")

check("something was actually assembled", total_written > 0,
      "every image is empty. An empty file still has a sha256, and printing "
      "one reads like a successful build.")

# --- the ABI table has to be AT its address, in the built image ------------
#
# `fill $FF,ABI_BASE-*` pads the code out to the table, and if the code ever
# reached past ABI_BASE that count is NEGATIVE - a negative repeat is an empty
# list and a negative size, so the table would be laid down wherever the code
# happened to end, with no diagnostic. Every paged call goes through
# ABI_BASE + n*3, so that is fifty-five slots pointing at the wrong routines.
#
# tests/test_abi_table.py checks the whole table and its targets; this is the
# same question asked one step earlier, so a build that has gone wrong says so
# before any gate runs. It costs one byte read.
_a2u12 = os.path.join(BUILD, "a2u12_lwasm.bin")
if os.path.exists(_a2u12):
    _image = open(_a2u12, "rb").read()
    # READ THE BOUNDARY, do not assume it. This was 0xF000 hard-coded in three
    # places on this line and the next two, and ABI_BASE moved to $EF90 on
    # 2026-09-18 to give the tail the fill that was sitting below it. A gate
    # that carries its own copy of a constant checks the constant it remembers
    # rather than the one the image was built with.
    _abi = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "common", "abi.inc")
    # AND NO FALLBACK VALUE. This read the file and kept 0xF000 when the regex
    # did not match, which is the fault the paragraph above describes wearing a
    # disguise: the table now starts at $EF90 and runs 165 bytes, so a JMP sits
    # at $F000 as well, and the check would have PASSED against an address it
    # had invented. A boundary that cannot be read is a build that must stop.
    with open(_abi, encoding="utf-8") as _fh:
        _m = re.search(r"^ABI_BASE\s+equ\s+\$([0-9A-Fa-f]+)", _fh.read(),
                       re.M)
    if not _m:
        raise SystemExit("build.py: ABI_BASE could not be read from "
                         f"{_abi}. The image's own boundary is not knowable, "
                         "so the table cannot be checked and the build stops.")
    _base = int(_m.group(1), 16)
    _at = _base - 0x8000
    check(f"the ABI jump table is at ${_base:04X} in the built image",
          len(_image) > _at and _image[_at] == 0x7E,
          f"${_image[_at]:02X} at ${_base:04X}, and a JMP is $7E. Either the code "
          f"ran past ABI_BASE and the fill went negative, or something is "
          f"defined between the table's entries - both leave every paged call "
          f"landing inside an instruction."
          if len(_image) > _at else "the image is too short to hold it")

# Completeness is what the gates say, not what the byte count says. The
# previous test here was `total_written == total_budget` - code bytes equal to
# the sum of the part sizes - which is true only if every image exactly fills
# its device with no padding at all, so it could never fire and the hashes it
# guarded were never printed.
if not failures:
    print("\n     every gate passed; the images and their hashes:")
    for name in IMAGES:
        lw = os.path.join(BUILD, f"{name}_lwasm.bin")
        if os.path.exists(lw):
            digest = hashlib.sha256(open(lw, "rb").read()).hexdigest()
            print(f"       {name:12} {digest}")
    print("\n     Burn only as a SET. These five replace both devices at "
          "once; a rewritten A2U12 and the stock A2U13 cannot run together.")
    print(f"\n     {total_budget - total_written:,} bytes of the "
          f"{total_budget:,} available across both devices are unused.")

if failures:
    print(f"\nFAILED ({len(failures)}): {', '.join(failures)}")
    sys.exit(1)

# THE IMAGES ARE STAMPED WITH THE SOURCE THEY CAME FROM, and only now that
# they have actually been written. A gate has no other way to tell a fresh
# image from one built before the change it is meant to be testing: this
# project once ran a gate against a 12:38 image while comparing it with symbols
# exported at 13:26, and the gate reported on firmware that was no longer
# there. scripts/groundtruth.py's check_build reads this back.
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "scripts"))
from groundtruth import stamp_build                        # noqa: E402
stamp_build(BUILD)

print("\nPASSED")

# --- the gates -------------------------------------------------------------
# Run every test in tests/ as part of the build, rather than leaving them to
# be remembered. test_zero_offset.py was written, passed, and then sat unrun
# while the exact fault it exists to catch went into a new module; the build's
# two-assembler comparison found it instead, which is a slower and far more
# confusing way to learn the same thing.
# HP8904A_ASSEMBLE_ONLY: assemble, compare the two assemblers, check the sizes
# and the vectors - everything above - and stop there. make_roms.py uses it so
# it can run THIS script's gate suite and its own seventeen emulator gates at
# the same time instead of one after the other; both only read the images, and
# the images are finished by the time this returns. Run on its own, build.py is
# unchanged and still runs everything.
#
# It is a separate flag from HP8904A_IN_GATE deliberately. That one means "you
# are inside test_gates_can_fail and must not recurse", and giving it a second
# meaning would make the empty-tree gate depend on a fast path it knows nothing
# about.
#
# A CHECKOUT WITHOUT THE SUITES ASSEMBLES ONLY, AND SAYS SO. The public copy
# (scripts/publish.py) carries the source, the two assemblers and the images,
# not the emulator or the gates, so the run below has nothing to run. Without
# this it died on a missing test_emulator.py; with it, it does exactly what
# HP8904A_ASSEMBLE_ONLY does and prints which case it was. A checkout that has
# the suites is unaffected: both files exist and this is false.
_SUITES = [os.path.join(ROOT, "emulator", "tests", "test_emulator.py"),
           os.path.join(ROOT, "hp8904a-rewrite", "tests", "run_all.py")]
_no_suites = not all(os.path.isfile(p) for p in _SUITES)
if (os.environ.get("HP8904A_IN_GATE") or os.environ.get("HP8904A_ASSEMBLE_ONLY")
        or _no_suites):
    if os.environ.get("HP8904A_IN_GATE"):
        print("\n     the gates are not run: this build is inside "
              "test_gates_can_fail, and running them here recurses")
    elif _no_suites and not os.environ.get("HP8904A_ASSEMBLE_ONLY"):
        print("\n     assembled and cross-checked only: this checkout has no "
              "test suites")
    else:
        print("\n     assembled only: make_roms.py runs the gates itself, "
              "alongside its own")
    if failures:
        print(f"\nFAILED ({len(failures)}): {', '.join(failures)}")
        sys.exit(1)
    sys.exit(0)

# THE MEASURING INSTRUMENT FIRST. Nine of the gates below run the firmware on
# the emulator, so every one of them is a statement about the emulator as much
# as about the firmware - and the emulator's own tests were not in this chain
# at all. They are in `npm run rom:native-test` and `npm run rom:selftest`, so
# somebody running those was covered and somebody running build.py directly
# was not, with no sign of the difference.
#
# That gap is not theoretical here: the emulator had the keypad's any-key
# polarity and its column drive backwards, agreeing with the firmware, and
# every gate passed while neither was right.
# STARTED NOW, COLLECTED AFTER THE GATE SUITE. The emulator's own tests and
# the gate suite are independent - both only read the images assembled above,
# neither writes anything the other reads - so the eighty seconds these take
# need not be spent before the suite starts. The result is still checked, and
# still refuses; it is only the waiting that overlaps.
_emulator_tests = subprocess.Popen(
    [gate_python(), os.path.join(ROOT, "emulator", "tests",
                                  "test_emulator.py")],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

# HP8904A_PREBUILT: the five images were assembled above, so the gates below
# need not each re-run this script - and that is what lets run_all.py run them
# concurrently instead of one at a time.
_emu_out, _emu_err = _emulator_tests.communicate()
emulator_tests = subprocess.CompletedProcess(
    [], _emulator_tests.returncode, _emu_out, _emu_err)
check("the emulator's own tests pass", emulator_tests.returncode == 0,      "\n".join(line for line in
                (emulator_tests.stdout + emulator_tests.stderr).splitlines()
                if line.startswith("FAIL"))[:600]
      + "  - every gate that runs the firmware is a statement about the "
        "emulator too, so a broken model makes all of them meaningless "
        "rather than failing")

gates = subprocess.run([gate_python(),
                        os.path.join(ROOT, "hp8904a-rewrite", "tests",
                                     "run_all.py")],
                       capture_output=True, text=True,
                       env=dict(os.environ, HP8904A_PREBUILT="1"))
print("\n     the gates:")
for line in gates.stdout.splitlines():
    if line.strip():
        print(f"     {line}")
check("every gate in tests/ passes", gates.returncode == 0,
      "\n".join(line.strip() for line in gates.stdout.splitlines()
                if line.strip().startswith("FAIL"))[:1500]
      or "run_all.py failed without a FAIL line; its stderr: "
      + gates.stderr[-600:])

if failures:
    print(f"\nFAILED ({len(failures)}): {', '.join(failures)}")
    sys.exit(1)

