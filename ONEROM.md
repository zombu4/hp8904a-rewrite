# A2U13 on a One ROM

## What the One ROM is

[One ROM](https://onerom.org) is a small board that plugs into a 28-pin EPROM
socket in place of the chip, and serves ROM images from an RP2350
microcontroller instead of from EPROM. It is programmed over USB, so changing
the firmware means re-flashing a board rather than erasing and burning a chip.
The board used here is the **fire-28-a3**.

## Why the 8904A needs a special build

A2U13 in the 8904A is a **27513**: a 64 KB EPROM that shows the instrument only
16 KB at a time. It has four 16 KB pages, and a latch inside the chip selects
one of them. The firmware selects a page by *writing* the page number to the
ROM. A plain 27C512 has no latch, so it cannot stand in for a 27513.

Standard One ROM firmware serves a fixed image and has no latch. The image in
this repository adds one:

- **The page latch.** The board holds all four pages and switches between them
  when the instrument writes to it. It latches only when `/WE` is low, `/CE` is
  low **and** `/OE` is high, as the 27513 does. A first version latched on
  `/WE` alone, and the instrument came up with display line 2 garbled, keys
  beeping, and then locked.
- **A fifth, writable bank.** Writing `$34` selects a fifth bank, which is
  RAM that the board copies to its own flash whenever it changes and reloads
  at power-on. This firmware keeps the serial number, the installed options
  and the twelve save/recall registers there. With the One ROM fitted, they
  are designed to survive a flat backup battery. That has been tested in the
  One ROM emulator, including a write torn by power loss, but not by pulling
  the battery on an instrument. The battery-backed RAM keeps its working copy
  at the usual addresses; at boot the bank's copy is written over it.

  On a genuine 27513 the firmware finds no fifth bank and runs from
  battery-backed RAM alone, exactly as before. Nothing has to be configured
  either way.

## The image

| file | bytes | sha256 |
| --- | ---: | --- |
| `roms/onerom/hp8904a-a2u13-onerom-fire28a3.bin` | 196,608 | `15055c06239e6b2a4d70222d30ba3d8197f720279d3026f0f96233e0fdd2ab9b` |

It is complete: the One ROM firmware (version 0.7.2 with the latch added) and
the four A2U13 pages from `roms/pages/`. Nothing else is needed to flash it.

The pages are stored in the order **0, 2, 1, 3**, not 0, 1, 2, 3. On the
fire-28-a3, data lines D0 and D1 reach the microcontroller swapped, so the page
number the instrument writes arrives bit-reversed: pages 1 and 2 trade places.
The image already allows for this. It matters only if you build your own image.

**It goes with `roms/rewrite_a2u12.bin` in A2U12.** This A2U13 does not run with
HP's A2U12, and HP's A2U13 does not run with this A2U12.

## Flashing it

You need the One ROM command-line tool, `onerom`, from
<https://onerom.org/cli>. One ROM also offers a browser tool and a desktop app;
the command-line tool is the only one this board has been flashed with.

1. **Check the file.**

       shasum -a 256 roms/onerom/hp8904a-a2u13-onerom-fire28a3.bin

   It must print `15055c06…ab9b` as above.

2. **Connect the board by USB, out of the instrument.**

       onerom scan

   This should list the board. **`State: Stopped` and a dark status LED are
   normal here:** while USB power is present, this firmware goes to the
   bootloader at start-up instead of serving. That is what lets it be flashed.

3. **Flash and verify.**

       onerom program --firmware roms/onerom/hp8904a-a2u13-onerom-fire28a3.bin --verify

   If your `onerom` has `--scan-slots`, add it. It reads the slot table back
   after flashing, and the four slots should name pages 0, 2, 1, 3 in that
   order.

4. **Unplug USB and fit the board** in the A2U13 socket, pin 1 to pin 1 as the
   27513 sat, with the instrument off. It serves only from socket power with
   USB unplugged.

5. **Power on.** The instrument's own Diagnostics → ROM Checks tests both ROMs.

Keep your original 27513 and A2U12. They are the way back.

## License

The One ROM firmware is © Piers Finlayson, MIT License; see
[roms/onerom/LICENSE-one-rom.md](roms/onerom/LICENSE-one-rom.md). The A2U13
pages it carries are this repository's own; see [LICENSE.md](LICENSE.md).
