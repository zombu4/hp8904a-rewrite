# HP 8904A serial-number and option recovery

**If your 8904A shows `Serial No 00000` and has lost its options after a
backup-battery change, this is the fix.** HP's answer was to replace the A2
Digital Assembly. You do not have to.

    roms/a2u12_recovery.bin
    32,768 bytes
    sha256  d9e127500e4ed36fc80a9967a90d11834c5016717b57156509107477bdbe0d3c

The image is in [`roms/`](roms/). This file is the procedure.

**This image is for an instrument still running HP's own firmware, revision
27887A.** It is HP's A2U12 with eight instructions added, and it runs with
HP's A2U13. The replacement firmware in this repository does not need it: its
serial and option screens have no lock to get past.

Burn it to a 27C256 and fit it in the **A2U12** socket, with HP's own A2U13
in place. It is a normal 27887A A2U12 image plus eight instructions.

---

## Why the instrument locks you out

Firmware revision 27887A has two guards that between them make a flat battery
unrecoverable from the front panel:

| screen | refuses when |
| --- | --- |
| serial installation, page 3 `$7163` | the serial is **not** `$0AAE60`, the factory-virgin value |
| option installation, page 3 `$6E81` | the serial **is** `$0AAE60`, **or** is `$000000` |

A dead battery leaves the serial at `$000000`. The serial screen refuses it for
not being virgin; the option screen refuses it for being zero. Neither can be
reached from the other.

**The service manual documents this procedure against a different firmware
revision, and that is worth knowing before you follow either.** HP part
08904-90008, Fourth Edition, `rev.01JUL91`, covers serial prefixes 2712A to
2948A, and every example display printed on its pages 8-43 to 8-48 reads
`Firmware Revision 18387A` — not 27887A. Every keystroke, softkey, timeout and
display string on those pages was read by eye against this instrument's
firmware and they agree; what does not carry over is the analysis above, which
was derived from the 27887A ROM in this repository and says nothing about
18387A.

HP's own pages also disagree with themselves about Option 005: the heading on
page 8-46 reads "OPTIONS 001, 003, AND 005", the step on page 8-45 says
"Options 001 and/or 003", and the running footers say one thing on 8-46 and
the other on 8-47 and 8-48. This file's finding that only bits 0 and 1 of
`installed_options` are ever tested is a statement about the 27887A ROM, made
by enumerating every read of `$3FFC` across all five images; it is not a claim
about what HP printed.

HP service note **8904A-05**, *"Procedure For Restoring RAM Data"* (24 September
1993), works around this by writing `0A AE 60` into `$3FFD` with a raw-address
memory editor reached through the service menu. **That editor does not exist on
27887A.** Its Memory Map Access screen walks seven fixed elements — `$0200`,
`$0400`, `$0900`, `$0B00`, `$0C00`, `$0D00`, `$1000` — and every one is I/O.
RAM cannot be reached from the front panel at all.

So the three bytes are written by the ROM instead.

## What this image adds

Eight instructions in `foreground_main_loop`, after `power_on_init` has
returned:

    ldd  >$3ffd          ; the first two bytes of the serial
    bne  done
    ldb  >$3fff          ; the third
    bne  done
    ldd  #$0aae
    std  >$3ffd
    ldb  #$60
    stb  >$3fff
    done:

It writes **exactly the three bytes HP's own service note names**, and only
when all three read zero — a state the instrument can only be in after losing
its battery. On an instrument whose serial is intact it does nothing at all.

It runs after `power_on_init` deliberately. Placed earlier it ran before the
firmware's own recovery path, which zeroes the serial when the RAM signature
check fails, and the seed was written and wiped in the same boot. The simulator
found that.

## The keys you need

All of these are the **blue** legends above a key — press `SHIFT` (the blue key,
bottom left) then the key under the legend.

| what you press | where it is |
| --- | --- |
| `SHIFT` | the blue key, bottom-left of the UTILITY block |
| `SPECIAL` | blue above `LAST`, in the DISPLAY block |
| `END` | blue above `rad/ENTER`, bottom-right of the DATA keypad |
| `PRESET` | blue above the backspace key `←`, right of the DATA keypad |
| `f1` `f2` `f3` `f4` | the four grey softkeys, left of the DISPLAY block |
| `ENTER` | the `rad/ENTER` key itself |

## Where to find your serial number

**On the rear panel**, on the HP serial label:

    SER 1234A56789
        └───┘└───┘
        prefix suffix

**The instrument wants only the last five digits — the suffix.** For
`SER 1234A56789` you key in `56789`. The prefix is not entered.

Below, `S S S S S` means **your** five serial digits and `C C C C C C C C`
means **your** six-digit option code. Do not key in the examples.

## Procedure

### 0. See what you have now

    SHIFT  PRESET

Two lines for about three seconds, then it times out. Press it again as often
as you like.

    HP 8904A Opts 02
    Firmware Revision 27887A Serial No 00000

`Serial No 00000` and nothing after `Opts 02` is the fault this ROM fixes. If
your serial already reads correctly, you do not need this ROM.

### 1. Fit this ROM and power on

Nothing to press, nothing displayed, no delay — the seed is silent. You should
get the normal screen:

    *    HP 8904A Main Selection Level    *
    f1 Channel Config.

The serial is now at the factory-virgin value, which is what unlocks step 2.

### 2. Serial number

    SHIFT  SPECIAL  8  7  ENTER  SHIFT  END

> After `SHIFT SPECIAL` the display should read `f1 Special # 0`. After `8 7`
> it should read `Special #87`. After `ENTER` the instrument beeps.

    ***** Serial Number Installation *****
    Enter 5 digit serial number. S/N=

Key in **your** five digits, then `ENTER`:

    S  S  S  S  S     ENTER

    Press SHIFT f2 to install S/N = SSSSS.
    If S/N is wrong use f3 Reenter f4 Exit.

**Read the display and check it against the rear-panel label.** `f3` re-enters,
`f4` exits, and the backspace key `←` fixes a typo while you are still keying.

    SHIFT  f2

    ***** Serial Number Installation *****
    Serial Number S/N = SSSSS installed.

**This is the only irreversible step.** The firmware will not let you change it
afterwards.

> **`Serial number cannot be installed.`** means the serial is not at the
> virgin value — this ROM is not fitted, or did not run. Check the image you
> burned.

### 3. Each option

    SHIFT  SPECIAL  4  8  ENTER  SHIFT  END

> After `4 8` the display should read `Special #48`.

    **** Option Firmware Installation ****
    Enter installation code:        f4 Exit

Key in **your** six-digit code, then `ENTER`:

    C  C  C  C  C  C     ENTER

    The presently installed options are:
    HP 8904A Opts 02/01

After about ten seconds:

    **** Option Firmware Installation ****
    Turn off LINE power to invoke options!!

**Power-cycle.** Repeat this step for each further option.

> **`Option installation not performable.`** means the serial number has not
> been entered. Go back to step 2 — do not retry the codeword. HP's own note
> gives a second possibility as well, and it is fair to repeat it: the service
> manual (08904-90008, page 8-47, NOTE e) says the instrument "will need its
> serial number entered **or it is in need of repair**". This file used to give
> the first cause alone, which reads as though it were the only one.

#### Getting your codeword

On a label **inside** the instrument — top cover off, right-hand side of the
chassis as you face the front, toward the rear. One per option:

    SER SSSSS
    OPT 001 CODE CCCCC

The entry field is **six digits** — `LDB #$06` at `$6F5A` sets its width — so
pad the codeword with leading zeros to six. A codeword of `12345` is entered as
`012345`.

For the second and later options the six digits are
`bit_index * 65536 + codeword`, where bit 0 is Option 001 and bit 1 is the slot
that prints `/03`. So a bit-1 codeword of `12345` is entered as
`1 * 65536 + 12345 = 077881`. That arithmetic is not guessable from a label
showing only the codeword, which is why it is spelled out here — and
`codeword.py` prints the finished six digits so you do not have to do it.

Six is enough for every case by design: the largest possible entry is bit 7
with a full 16-bit codeword, `7 * 65536 + 65535 = 524287`.

**If the label is missing**, compute it from your serial:

    python3 firmware/codeword.py SSSSS

It prints the codeword and the six digits to key in, for every option bit.

### 4. Check

    SHIFT  PRESET

    HP 8904A Opts 02/01/03
    Firmware Revision 27887A Serial No SSSSS

Your serial, and your options after `Opts 02`.

### 5. Swap back to the ordinary ROM

This one has done its job. Everything you entered lives in battery-backed RAM
and stays there. There is no reason to leave a ROM that writes `$3FFD`
permanently in the instrument.

Keep this image on a **UV-erasable** part as your recovery tool, and write your
serial and codewords down somewhere that is not inside the instrument — which
is where they were when the battery died.

## Computing a lost codeword

HP describes the codeword only as *"unique to the serial number and option
number"*. The algorithm is `option_authorisation_code` at A2U13 page 3 `$6904`,
recovered from the instruction stream:

1. seed a 16-bit accumulator with the word at `$3FFE` — the low two bytes of
   the 3-byte serial at `$3FFD`;
2. repeat `option_number + 1` times: fill a 20-byte buffer with the accumulator
   repeated big-endian, then replace the accumulator with the bit-serial LFSR
   signature of that buffer, computed by `lfsr16_block_signature` (`$6850`);
3. the result is the codeword.

The six digits you key in are `option_number * 65536 + codeword`, where the
option number is the **bit index** in `installed_options` (`$3FFC`), not HP's
three-digit option number. Bit 0 is Option 001; bit 1 prints `/03`. The
firmware right-justifies your six characters to eight inside its own buffer
with `$B223` before converting them, which is why the internal code deals in
eight while the field you type into is six.

**This is confirmed against hardware.** Run for option 0 with serial suffix
`01611` — seed `$064B` — it returns **14517**, and the factory label inside
`SER 2843A01611` reads `OPT 001 CODE 14517`. Exact agreement, first attempt,
against a label printed at the factory around 1988.

`firmware/codeword.py` computes it.

## What actually depends on the option bits

`installed_options` (`$3FFC`) is read in **twelve** places across the five
images and written in three. Eight reads apply a mask, and the mask is always `#$01` or `#$02` — so **bits
0 and 1 are the only ones that do anything.** Bits 2–7 are never tested and
print nothing; a `/05` in a banner on some other firmware revision has no
effect here.

**Bit 0 — Option 001**

| where | what it gates |
| --- | --- |
| A2U12 `$893F` | loads `$2223` from the paged table; clear zeroes it. `$2223` is the upper bound of the main-menu index at `$2245`, so with the bit clear `NEXT`/`LAST` find only one menu entry |
| A2U12 `$8970` | installs three mode handlers into `$2224` onward — Tone Sequence, DTMF Sequence, Digital Sequence. Clear, it installs the do-nothing stub `$C239` |
| page 0 `$54A3` | a branch in `enter_channel_config_mode` |
| page 0 `$5D72` | a branch in the UI event dispatch |
| page 0 `$5FE6` | **clear raises error `$1F`, "Option FW needed for DESTN control"** — this is what the instrument says if you try to change a channel's destination without it |

**Bit 1 — Option 003**

| where | what it gates |
| --- | --- |
| page 0 `$5495` | a branch in `enter_channel_config_mode`, taken before the bit-0 test |
| page 0 `$5D69` | the UI event dispatch: the special path needs bit 1 **set and bit 0 clear** |
| page 0 `$604E` | the destination-key path |

**Unmasked**

`$800B` reads the whole byte for the banner text, and `$6DD8` in
`install_option_from_auth_code` reads it to OR in the new bit.

## The image

    roms/a2u12_recovery.bin    32,768 bytes
    sha256 d9e127500e4ed36fc80a9967a90d11834c5016717b57156509107477bdbe0d3c

It was assembled from a byte-exact disassembly of HP's 27887A A2U12 with the
eight instructions above added, and held to a RAM-safety check that refuses
any undeclared write to `$2000-$3FFF` and verifies that these two stores are
guarded and unreachable unless the serial already reads zero. HP's disassembly is not
distributed here; see the README.

## Warnings

`$3FFC`-`$3FFF` hold your instrument's identity and there is no checksum over
any of it. Do not hand-edit this image. Do not write to those addresses by any
other route.

Keep your original A2U12 ROM. It is the only stock copy in your instrument and
it is the way back if anything here misbehaves.
