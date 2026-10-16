#!/usr/bin/env python3
"""Compute an HP 8904A option installation codeword from the serial number.

    codeword.py <5-digit serial suffix> [--option N]

HP prints these on a label inside the instrument, right side of the chassis
toward the rear, and describes them only as "unique to the serial number and
option number" (Service Manual 08904-90008, section 8-46). The algorithm was
never published. This is it, recovered from the instruction stream:

  option_authorisation_code ($6904, A2U13 page 3)
      seed a 16-bit accumulator with the word at $3FFE - the low two bytes of
      the 3-byte serial number at $3FFD - then repeat, option+1 times:
          fill a 20-byte buffer with the accumulator, repeated big-endian
          replace the accumulator with lfsr16_block_signature() of that buffer

  lfsr16_block_signature ($6850)
      a bit-serial 16-bit LFSR over the buffer. For each of the 8 bits of each
      byte it sums, into A, the carries out of: two ASLB on the low half
      (accumulator bit 6), one ASRB on the high half (bit 8), three more ASRB
      (bit 11), a following ASLB (the replicated sign, bit 15), and ASL of the
      current data bit. ASRA then leaves the parity of those five in the carry,
      and ROL/ROL shifts it into the accumulator.

CONFIRMED AGAINST HARDWARE. For option 0 with serial suffix 01611 - seed $064B
- this returns 14517, and the factory codeword label inside instrument
SER 2843A01611 reads "OPT 001 CODE 14517". Exact agreement, first attempt.

The number keyed into the instrument is option_number * 65536 + codeword,
padded with leading zeros to SIX digits - the on-screen entry field is six
characters wide, set by LDB #$06 at $6F5A. The firmware then right-justifies
those six to eight inside its own buffer with $B223 before converting them,
which is why the internal code deals in eight while the field you type into is
six. Six is enough for every case by design: the largest possible entry is bit
7 with a full 16-bit codeword, 7 * 65536 + 65535 = 524287.

option_number is the BIT INDEX in installed_options ($3FFC) and not HP's
three-digit option number. Bit 0 is Option 001; bit 1 prints /03 in the
banner.
"""

import argparse
import sys


def signature(data):
    """The bit-serial LFSR signature at $6850, over a sequence of bytes."""
    high = low = 0
    for byte in data:
        current = byte
        for _ in range(8):
            total = 0
            register = low                      # ldb 5,s
            register = (register << 1) & 0xFF   # aslb
            carry = (register >> 7) & 1
            register = (register << 1) & 0xFF   # aslb
            total = (total + carry) & 0xFF      # adca #$00
            register = high                     # ldb 4,s
            carry = register & 1
            register = ((register >> 1) | (register & 0x80)) & 0xFF   # asrb
            total = (total + carry) & 0xFF
            for _ in range(3):                                        # asrb x3
                carry = register & 1
                register = ((register >> 1) | (register & 0x80)) & 0xFF
            total = (total + carry) & 0xFF
            carry = (register >> 7) & 1
            register = (register << 1) & 0xFF                         # aslb
            total = (total + carry) & 0xFF
            carry = (current >> 7) & 1                                # asl 2,s
            current = (current << 1) & 0xFF
            total = (total + carry) & 0xFF
            parity = total & 1                                        # asra
            low, high = (((low << 1) | parity) & 0xFF,                # rol 5,s
                         ((high << 1) | ((low >> 7) & 1)) & 0xFF)     # rol 4,s
    return (high << 8) | low


def codeword(option, serial_suffix):
    accumulator = serial_suffix & 0xFFFF
    for _ in range(option + 1):
        buffer = []
        for _ in range(0, 0x14, 2):
            buffer.append((accumulator >> 8) & 0xFF)
            buffer.append(accumulator & 0xFF)
        accumulator = signature(buffer)
    return accumulator


def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("serial", help="the 5-digit serial suffix, e.g. 01611 "
                                       "for SER 2843A01611")
    parser.add_argument("--option", type=int,
                        help="a single option bit index; omit for all eight")
    args = parser.parse_args()

    try:
        suffix = int(args.serial, 10)
    except ValueError:
        print("error: the serial suffix is the last five DIGITS of the "
              "rear-panel serial number", file=sys.stderr)
        return 1
    if not 0 <= suffix <= 0xFFFFFF:
        print("error: that does not fit the 3-byte serial field",
              file=sys.stderr)
        return 1
    if suffix == 0:
        print("note: with the serial at zero the LFSR is seeded with zero, "
              "which is a fixed point, so every codeword computes to 0. "
              "Restore the serial first.", file=sys.stderr)

    print(f"serial suffix {suffix:05d}   seed ${suffix & 0xFFFF:04X}\n")
    wanted = [args.option] if args.option is not None else range(8)
    for option in wanted:
        value = codeword(option, suffix)
        entry = option * 65536 + value
        # Both strings here used to be wrong, and nothing checked them:
        # the description checker covers routines, not a tool's own
        # output. Bit 1 is NOT display-only - at page 0 $5495 it sets the
        # Channel Config menu limit $2242 to 6 instead of 4, which is the
        # only thing that makes the Hop Ram and Digital Port pages reachable,
        # and it is the sole gate on the hop-field key chain at $604E. So
        # bit 0 was not "the only bit with any effect" either. Both readings
        # are corroborated by the manual's own retrofit wording on page 7-1.
        banner = {0: "  banner /01 - Option 001, three internal channels, "
                     "modulation, summation and sequence",
                  1: "  banner /03 - Option 003, fast hop and digital "
                     "modulation"}.get(option, "")
        print(f"  bit {option}   codeword {value:5}   key in "
              f"{entry:06d}{banner}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
