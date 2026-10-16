# HP 8904A replacement firmware

New firmware for the **HP 8904A Multifunction Synthesizer**, written in MC6809
assembly. It replaces both firmware chips on the A2 Digital Assembly: **A2U12**
(32 KB, always mapped) and **A2U13** (64 KB, four 16 KB pages). Every routine
of HP's revision 27887A firmware was read and ported. The result builds as one
program across the two parts and reports itself as revision **RW0001**.

This repository contains:

- the source,
- the ready-to-burn images,
- a recovery image for instruments still on HP's firmware that lost their
  serial number and options to a flat backup battery.

Not affiliated with HP, Agilent or Keysight. "HP" and "8904A" are used only
to name the instrument this runs on.

## The images

| socket | file | part | bytes | sha256 |
| --- | --- | --- | ---: | --- |
| A2U12 | `roms/rewrite_a2u12.bin` | 27C256 | 32,768 | `b484027b9944e2da9bd7bece7511510064f59aa391c0c80e84d146f7bc071ea6` |
| A2U13 | `roms/rewrite_a2u13.bin` | 27513 (page-latched; not a plain 27C512) | 65,536 | `76e402d8848e3f6c4428ef903f300d7cdd96671ff3cc2c285787537aa7a62bb5` |

**Burn both parts or neither.** This A2U12 does not run with HP's A2U13, and
HP's A2U12 does not run with this A2U13.

Check the files before you burn:

    shasum -a 256 roms/rewrite_a2u12.bin roms/rewrite_a2u13.bin

### A2U13 as four pages

`roms/pages/` holds A2U13 split into its four 16 KB pages, for page-switching
carriers that take separate page files. On the One ROM fire-28-a3 carrier the
pages load in slot order **0, 2, 1, 3**. That order was found on the bench for
that carrier; it is not a property of the 27513.

| slot | file | sha256 |
| ---: | --- | --- |
| 1st | `roms/pages/rewrite_a2u13_page0.bin` | `40828c6d63729b4287b9f78052d680e878cc1843204c9f357b9fa7831e039b27` |
| 2nd | `roms/pages/rewrite_a2u13_page2.bin` | `c65dadb26afb27e77b25d2c406a6c53131bd3bca259114f5caeef3d9ed23fdd3` |
| 3rd | `roms/pages/rewrite_a2u13_page1.bin` | `4d9c9c010ab9d2bb079617cfb4f386e1f0afed4acdb1d51d0347b1952ac9e011` |
| 4th | `roms/pages/rewrite_a2u13_page3.bin` | `a720e60ec41005bc4778224a400d6cc19bbd913f75e85922a2fbef760750e86b` |

The first byte of each page is the ASCII digit of its own page number. The
firmware reads that byte back to prove the page switched:

    for n in 0 1 2 3; do head -c1 roms/pages/rewrite_a2u13_page$n.bin | xxd -p; done    # 30 31 32 33

## Before you burn

**Keep your original ROMs.** They are the way back.

The instrument's identity lives in battery-backed RAM: serial number at
`$3FFD`, installed options at `$3FFC`, revision signature at `$3FF6`, and a
legacy byte at `$3FF2`. This firmware never moves or clears those bytes, so
they survive the change in both directions. Registers saved by HP's firmware
read as empty here ("No recall setting in this register").

## Where it differs from HP's firmware

These differences are on purpose:

- **Serial number and options.** The serial can be written at any time, and
  each option bit can be set and cleared on its own, with no codeword. On HP's
  27887A a flat battery locks both out (see [RECOVERY.md](RECOVERY.md)), and
  an option bit, once set, can never be cleared.
- **Firmware revision.** The ID reply gives RW0001, not 27887A, so a
  controller can tell which firmware it is talking to.
- **TALK lamp.** It goes out when the controller untalks the instrument. On
  HP's firmware it stays lit.
- **Digital Sequence levels.** Re-selecting a level between a number and its
  unit sets 0. HP's firmware sets a value left over from the previous number.
- **`ST_ID`** does not copy work-cell bytes into the serial number.

These features are additions:

- **FM Stereo**, a screen of its own on the Main Selection Level.
- **Backlight timeout.** HP's firmware has a fixed timeout of about three
  minutes. Here it is settable, including Off.
- **Relay exercise**, under Diagnostics. It cycles the output relays to
  clean their contacts. Press UP to start; any key stops it and puts every
  relay back. NEXT or LAST switches between two sets: every relay, or the 48 dB
  attenuator relay (K8) alone. K8 is the only armature relay on the output
  board; the others are reeds. It runs at about 24 cycles a second, which is
  about 1,400 operations a minute on every relay, so do not leave it running
  unattended.

## Building the images yourself

You need Python 3 and `lwasm` from [LWTOOLS](http://www.lwtools.ca/). The
build has been checked with lwasm 4.25.

    python3 hp8904a-rewrite/build.py

Each source image is assembled twice, by `lwasm` and by this repository's own
`firmware/asm6809.py`. The build refuses unless the two agree byte for byte.
It finishes with `PASSED` and writes to `hp8904a-rewrite/build/`:

    a2u12_lwasm.bin                      A2U12
    a2u13_page0_lwasm.bin .. page3       the four A2U13 pages

Join the pages into one A2U13 image and compare both with the published ones:

    cd hp8904a-rewrite/build
    cat a2u13_page0_lwasm.bin a2u13_page1_lwasm.bin a2u13_page2_lwasm.bin a2u13_page3_lwasm.bin > a2u13.bin
    cmp a2u12_lwasm.bin ../../roms/rewrite_a2u12.bin && cmp a2u13.bin ../../roms/rewrite_a2u13.bin && echo identical

Built from this repository unchanged, both files are byte-identical to the
images in `roms/`.

### Layout

    hp8904a-rewrite/build.py     the build
    hp8904a-rewrite/images/      one top-level source per image
    hp8904a-rewrite/modules/     the firmware, one file per subsystem
    hp8904a-rewrite/common/      shared definitions: RAM map, I/O, ABI table
    firmware/asm6809.py          the second assembler, and mc6809.py its
                                 instruction table
    firmware/codeword.py         option codeword calculator (see RECOVERY.md)
    scripts/                     two helpers build.py imports
    roms/                        the images

Every source file says what it does and why, including where the routine came
from in HP's firmware, by address.

## Not in this repository

HP's own firmware images and service manual are not distributed here.

- HP's ROM dumps and their disassembly are published by
  [namasl/hp8904a-gpib-fix](https://github.com/namasl/hp8904a-gpib-fix).
- The service manual (08904-90008) is on Keysight's site:
  <https://www.keysight.com/us/en/assets/9018-40471/reference-guides/9018-40471.pdf>

Neither is needed to build these images.

## License

[PolyForm Noncommercial 1.0.0](LICENSE.md). Free for personal, hobby,
educational, research and non-profit use. Selling it, bundling it with a
product, or any other commercial use requires permission from the author.
