#!/usr/bin/env python3
"""What every tool and gate here must prove before it is allowed to report.

    python3 scripts/groundtruth.py            # check everything, say what it is

THE SHAPE OF THE FAULT THIS EXISTS TO STOP. Three separate failures in this
project are one shape: a tool measured something other than what it claimed
to be measuring, and the number it produced looked perfectly reasonable.

  - scripts/index.py assembled the stock sources with --relax and published
    addresses from a SHORTER PROGRAM. 1687 of 2097 routines were at the wrong
    address, a2u13_page0 by up to 819 bytes, and $52F4 - offered as
    sequence_mode_init - is the middle of an instruction. Every port is
    checked against that file before a listing is read.
  - the emulator gates ran on a model that differed from the real MC6840,
    P8291A and HD44780 in twenty-five ways. Every gate passed. They were
    proving things about a machine that does not exist.
  - a register test asserted the format-4 marker while reading format-3
    offsets, and passed.

None of these is caught by anything, because a WRONG MEASUREMENT PRODUCES A
PLAUSIBLE ANSWER, and a broken gate that always passes looks exactly like a
gate that found nothing. The only defence is for each tool to state what its
ground truth is and REFUSE TO REPORT until it has verified it has that ground
truth - and for each refusal to have been SEEN to happen, because a check
nobody has watched refuse is not a check.

THE THREE GROUND TRUTHS, and what each means:

  stock      the five images under firmware/ are the ORIGINAL ROMs, byte for
             byte, against the SHA-256 pins in firmware/UPSTREAM.md. Every
             comparison in this project treats them as the instrument, so if
             one of them is a rebuild or a patched variant, every "the stock
             does X" in the tree is a statement about something else.
  sources    the generated stock sources reassemble to those ROMs exactly.
             They are a disassembly, and their only value is that. This is
             what --relax broke.
  build      the rewrite images a gate is about to test were built from the
             source as it stands NOW. A gate run against yesterday's image
             reports on yesterday's firmware and says nothing about the
             change just made - which happened here twice, once comparing
             a 12:38 image against symbols exported at 13:26.

Each is a function that returns quietly or raises GroundTruthLost. Nothing
here prints on success: a tool that says "ground truth ok" every run teaches
its reader to skip the line.
"""
import hashlib
import io
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FIRMWARE = os.path.join(ROOT, "firmware")
GENERATED = os.path.join(FIRMWARE, "src-generated")
REWRITE = os.path.join(ROOT, "hp8904a-rewrite")

# THE ASSEMBLER IS A TOOL, NOT DATA, so its path is frozen here and does not
# follow FIRMWARE. A caller that repoints FIRMWARE at a copy - which is how
# test/test_groundtruth.py breaks a source without touching the real one -
# must still run the real assembler, or the refusal it sees is the copy
# failing to import rather than the source failing to be the ROM.
ASSEMBLER = os.path.join(FIRMWARE, "asm6809.py")

# The images every comparison in this project calls "the instrument".
STOCK_IMAGES = ["a2u12.bin", "a2u13_page0.bin", "a2u13_page1.bin",
                "a2u13_page2.bin", "a2u13_page3.bin"]

# What the build writes so a gate can tell a fresh image from a stale one.
STAMP = "source.stamp"

# Everything the five images are built from. A change to any of it makes the
# images in a build directory stale, and the stamp will not match.
SOURCE_DIRS = [("hp8904a-rewrite/modules", (".s", ".inc")),
               ("hp8904a-rewrite/common", (".s", ".inc")),
               ("hp8904a-rewrite/images", (".s",))]
SOURCE_FILES = ["hp8904a-rewrite/build.py", "firmware/asm6809.py"]


class GroundTruthLost(Exception):
    """Raised instead of reporting a number that would not mean anything."""


def _digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


# --- stock: the images are the original ROMs ---------------------------------
def upstream_pins():
    """name -> sha256, from firmware/UPSTREAM.md's own checksum block.

    Read rather than duplicated. A second copy of a hash in this file would
    be a second thing to keep in step, and the failure it is guarding against
    is exactly two records of one fact disagreeing.
    """
    path = os.path.join(FIRMWARE, "UPSTREAM.md")
    text = io.open(path, encoding="utf-8").read()
    # THE NAME MUST LOOK LIKE A FILE. The pattern was `(\S+)` after any run
    # of 64 hex characters, which keyed on whatever word came next - so the
    # table also held 'Intel', 'Motorola' and 'DS75160A,', picked up from
    # prose that happens to follow a hash. Harmless in itself, but it meant
    # the table could never be empty and so could never trip its own floor
    # below, and it made the "pinned names" list this prints useless.
    pins = {}
    for found in re.finditer(r"([0-9a-f]{64})\s+\.?/?(\S+\.(?:bin|pdf|zip))\b",
                             text):
        pins[os.path.basename(found.group(2))] = found.group(1)
    if not pins:
        raise GroundTruthLost(
            f"{path} carries no sha256 pins, so there is nothing to hold the "
            f"stock images to. Every 'the stock does X' in this tree rests on "
            f"those five files being the original ROMs.")
    return pins


def check_stock():
    """The five stock images are the upstream ROMs, byte for byte.

    THE FOUR PAGES ARE NOT PINNED SEPARATELY, and they should not be: upstream
    ships one 65,536-byte a2u13.bin, and firmware/split_a2u13.py slices it at
    N x $4000. So each page is held to the SLICE of the pinned whole rather
    than to a hash of its own. A second pin would be a second record of one
    fact, free to drift from it - which is the class of failure this whole
    file exists to stop. This check found that gap the first time it ran: the
    four pages were held to nothing at all.
    """
    pins = upstream_pins()
    wrong, unpinned = [], []
    for name in ("a2u12.bin", "a2u13.bin"):
        path = os.path.join(FIRMWARE, name)
        if not os.path.exists(path):
            wrong.append(f"{name}: missing")
            continue
        want = pins.get(name)
        if want is None:
            unpinned.append(name)
            continue
        got = _digest(path)
        if got != want:
            wrong.append(f"{name}: {got[:16]} against the pinned {want[:16]}")

    whole_path = os.path.join(FIRMWARE, "a2u13.bin")
    if not wrong and os.path.exists(whole_path):
        whole = io.open(whole_path, "rb").read()
        for page in range(4):
            name = f"a2u13_page{page}.bin"
            path = os.path.join(FIRMWARE, name)
            if not os.path.exists(path):
                wrong.append(f"{name}: missing")
                continue
            want = whole[page * 0x4000:(page + 1) * 0x4000]
            got = io.open(path, "rb").read()
            if got != want:
                at = next((i for i in range(min(len(got), len(want)))
                           if got[i] != want[i]), None)
                wrong.append(
                    f"{name}: not the slice of the pinned a2u13.bin at "
                    f"${page * 0x4000:04X}"
                    + (f", first differing at +${at:04X}" if at is not None
                       else f" - {len(got)} bytes against {len(want)}"))
    if unpinned:
        wrong.append("not pinned at all: " + ", ".join(unpinned))
    if wrong:
        raise GroundTruthLost(
            "the stock images are not the ROMs firmware/UPSTREAM.md pins:\n  "
            + "\n  ".join(wrong)
            + "\nEverything this project calls 'the instrument' is those "
              "files. Nothing is reported until they are the right ones.")


# --- sources: the disassembly reassembles to the ROM -------------------------
def check_sources(images=None):
    """Each generated source assembles, unrelaxed, to the ROM beside it.

    Their whole value is that they reproduce the ROM; an address or a byte
    read out of one that does not is an address in some other program.
    """
    import tempfile
    wanted = list(images or [n[:-4] for n in STOCK_IMAGES])
    # A MISSING SOURCE OR ROM IS THE LOUDEST CASE, NOT THE QUIETEST. This
    # loop used to `continue` past either, so an empty firmware/src-generated
    # made the whole function return without assembling anything - and every
    # caller reads a quiet return as "the disassembly IS the ROM".
    # check_sources_cached() then hashed the empty listing and wrote that
    # down as proof. check_stock() has always got this right; this did not.
    absent = [name for name in wanted
              if not (os.path.exists(os.path.join(GENERATED, name + ".s"))
                      and os.path.exists(os.path.join(FIRMWARE, name + ".bin")))]
    if absent:
        raise GroundTruthLost(
            "these have no generated source, or no ROM to hold it to, so "
            "there is nothing to verify and a quiet return would be read as "
            "verification: " + ", ".join(absent))
    if not wanted:
        raise GroundTruthLost(
            "no images were named and STOCK_IMAGES is empty, so this would "
            "have verified nothing and said so with silence")
    for name in wanted:
        source = os.path.join(GENERATED, name + ".s")
        rom = os.path.join(FIRMWARE, name + ".bin")
        with tempfile.TemporaryDirectory() as scratch:
            out = os.path.join(scratch, "image.bin")
            run = subprocess.run(
                [sys.executable, ASSEMBLER, source, "-o", out],
                capture_output=True, text=True)
            if run.returncode != 0:
                raise GroundTruthLost(
                    f"{name}: the generated source no longer assembles, so "
                    f"nothing read out of it is a fact about the ROM\n"
                    f"{run.stderr.strip()[:400]}")
            built = io.open(out, "rb").read()
        original = io.open(rom, "rb").read()
        if built != original:
            where = next((i for i in range(min(len(built), len(original)))
                          if built[i] != original[i]), None)
            raise GroundTruthLost(
                f"{name}: what the generated source assembles to is not the "
                f"ROM - {len(built)} bytes against {len(original)}"
                + (f", first differing at ${where:04X}" if where is not None
                   else "")
                + ". Addresses and bytes read from it would name a different "
                  "program. This is what --relax did to scripts/index.py.")


VERIFIED = os.path.join(GENERATED, ".assembles-to-the-rom")


def check_sources_cached():
    """check_sources, but only actually assembling when the sources changed.

    Five assembles is a few seconds, and the write guard runs
    capabilities.py on every sweep against a budget measured in milliseconds.
    The cache records the HASH OF THE SOURCES that were proven to reassemble,
    so it can only skip work for sources that have not moved since; any edit
    re-verifies. A cache keyed on anything weaker - a timestamp, a bare "ok" -
    would be one more record free to drift from the fact it stands for, which
    is the failure this file exists to stop.
    """
    mark = hashlib.sha256()
    for name in sorted(os.listdir(GENERATED)):
        if name.endswith(".s"):
            mark.update(name.encode())
            mark.update(_digest(os.path.join(GENERATED, name)).encode())
    for name in sorted(STOCK_IMAGES + ["a2u13.bin"]):
        path = os.path.join(FIRMWARE, name)
        if os.path.exists(path):
            mark.update(_digest(path).encode())
    now = mark.hexdigest()
    if os.path.exists(VERIFIED):
        if io.open(VERIFIED, encoding="utf-8").read().strip() == now:
            return
    check_sources()
    with open(VERIFIED, "w", encoding="utf-8") as handle:
        handle.write(now + "\n")
        handle.flush()
        os.fsync(handle.fileno())


# --- build: the images under test are the source as it stands now ------------
def source_mark():
    """One hash over everything the five images are built from."""
    mark = hashlib.sha256()
    for relative, suffixes in SOURCE_DIRS:
        base = os.path.join(ROOT, relative)
        if not os.path.isdir(base):
            continue
        for name in sorted(os.listdir(base)):
            if name.endswith(suffixes):
                mark.update(name.encode())
                mark.update(_digest(os.path.join(base, name)).encode())
    for relative in SOURCE_FILES:
        path = os.path.join(ROOT, relative)
        if os.path.exists(path):
            mark.update(relative.encode())
            mark.update(_digest(path).encode())
    return mark.hexdigest()


def stamp_build(build):
    """Record, in the build directory, the source these images came from."""
    os.makedirs(build, exist_ok=True)
    with open(os.path.join(build, STAMP), "w", encoding="utf-8") as handle:
        handle.write(source_mark() + "\n")
        handle.flush()
        os.fsync(handle.fileno())


def check_build(build):
    """The images in `build` were built from the source as it stands now."""
    path = os.path.join(build, STAMP)
    if not os.path.exists(path):
        raise GroundTruthLost(
            f"{build} carries no {STAMP}, so there is no way to tell whether "
            f"its images are this source or an older one. Build it: "
            f"HP8904A_ASSEMBLE_ONLY=1 python3 hp8904a-rewrite/build.py")
    was = io.open(path, encoding="utf-8").read().strip()
    now = source_mark()
    if was != now:
        raise GroundTruthLost(
            f"the images in {build} were built from a DIFFERENT source than "
            f"the one on disk now ({was[:16]} against {now[:16]}). A gate run "
            f"against them reports on firmware that is no longer here. Build "
            f"it again: HP8904A_ASSEMBLE_ONLY=1 python3 "
            f"hp8904a-rewrite/build.py")


# --- model: the emulator has passed its own fidelity suite -------------------
EMULATOR = os.path.join(ROOT, "emulator", "hp8904a.py")
FIDELITY = os.path.join(ROOT, "emulator", "build", ".fidelity-verified")


def emulator_mark():
    """The emulator's own source, and the fidelity suite that holds it."""
    mark = hashlib.sha256()
    for path in (EMULATOR,
                 os.path.join(ROOT, "emulator", "tests", "test_emulator.py")):
        if os.path.exists(path):
            mark.update(_digest(path).encode())
    return mark.hexdigest()


def record_fidelity():
    """Called by the fidelity suite itself, and only when it has passed."""
    os.makedirs(os.path.dirname(FIDELITY), exist_ok=True)
    with open(FIDELITY, "w", encoding="utf-8") as handle:
        handle.write(emulator_mark() + "\n")
        handle.flush()
        os.fsync(handle.fileno())


def check_model():
    """The emulator running these gates has passed its fidelity suite.

    THIS CANNOT PROVE THE MODEL IS THE SILICON, and it does not claim to.
    What it stops is the case that actually happened: the gates ran for weeks
    on a model that differed from the real MC6840, P8291A and HD44780 in
    twenty-five ways, every gate passed, and what they proved was true of a
    machine that does not exist. The fidelity suite is where those
    twenty-five are pinned to the datasheets; this refuses to let any gate
    run on an emulator whose own suite has not been seen to pass FOR THAT
    EXACT SOURCE. Editing the model silently invalidates it.
    """
    now = emulator_mark()
    if not os.path.exists(FIDELITY):
        raise GroundTruthLost(
            "the emulator has not been held to its fidelity suite on this "
            "source. Every gate here runs on that model, and it has been "
            "wrong in twenty-five ways before while every gate passed. Run "
            "it: python3 emulator/tests/test_emulator.py")
    was = io.open(FIDELITY, encoding="utf-8").read().strip()
    if was != now:
        raise GroundTruthLost(
            f"the emulator or its fidelity suite has changed since the suite "
            f"last passed ({was[:16]} against {now[:16]}). Until it passes "
            f"again, no gate run on this model means anything. Run it: "
            f"python3 emulator/tests/test_emulator.py")


# --- the whole set, for a tool that wants all three --------------------------
def check_all(build=None):
    check_stock()
    check_sources()
    check_model()
    if build:
        check_build(build)


def main():
    problems = []
    for name, run in (("stock", check_stock), ("sources", check_sources)):
        try:
            run()
            print(f"ok   {name}")
        except GroundTruthLost as lost:
            problems.append(name)
            print(f"FAIL {name}")
            for line in str(lost).splitlines():
                print(f"       {line}")
    build = os.environ.get("HP8904A_BUILD") or os.path.join(REWRITE, "build")
    try:
        check_build(build)
        print(f"ok   build  {build}")
    except GroundTruthLost as lost:
        problems.append("build")
        print(f"FAIL build  {build}")
        for line in str(lost).splitlines():
            print(f"       {line}")
    if problems:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
