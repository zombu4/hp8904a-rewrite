#!/usr/bin/env python3
"""MC6809 instruction table: encoding, mnemonic and addressing mode.

This table is written out explicitly rather than inferred from the existing
listings, because those listings come from a disassembler that also knows the
Hitachi 6309 and decodes two indexed postbytes its way. It is then held to
those listings as a test: `python3 mc6809.py --check a2u12.asm a2u13.asm`
walks all 40,426 decoded lines and reports every disagreement in mnemonic or
in length. Disagreements are findings, not failures — each one is looked at.

Addressing modes
    INHERENT   no operand
    IMM8       one operand byte          IMM16   two operand bytes
    DIRECT     one byte, page from DP    EXTENDED two-byte address
    INDEXED    postbyte, plus 0-2 more bytes decided by the postbyte
    REL8       signed 8-bit displacement REL16   signed 16-bit
    REGPAIR    TFR/EXG postbyte          STACK    PSHS/PULS/PSHU/PULU postbyte

Undefined opcodes are absent from the table. A disassembler must treat them as
data: about 1KB of both ROMs is undeclared data, and 109 lines of a2u12.asm
decode to opcodes the 6809 does not have.
"""

import argparse
import collections
import re
import sys

# Register codes valid in a TFR/EXG postbyte: D X Y U S PC and A B CC DP.
REGISTER_CODES = frozenset((0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x8, 0x9, 0xA, 0xB))

INHERENT, IMM8, IMM16 = "INHERENT", "IMM8", "IMM16"
DIRECT, EXTENDED, INDEXED = "DIRECT", "EXTENDED", "INDEXED"
REL8, REL16, REGPAIR, STACK = "REL8", "REL16", "REGPAIR", "STACK"

OPERAND_BYTES = {INHERENT: 0, IMM8: 1, IMM16: 2, DIRECT: 1, EXTENDED: 2,
                 REL8: 1, REL16: 2, REGPAIR: 1, STACK: 1}

# Unary memory/register operations, indexed by the low nibble.
UNARY = {0x0: "NEG", 0x3: "COM", 0x4: "LSR", 0x6: "ROR", 0x7: "ASR",
         0x8: "ASL", 0x9: "ROL", 0xA: "DEC", 0xC: "INC", 0xD: "TST",
         0xE: "JMP", 0xF: "CLR"}

# The $80-$BF block: accumulator A, plus the 16-bit X/D operations.
BLOCK_A = {0x0: ("SUBA", 1), 0x1: ("CMPA", 1), 0x2: ("SBCA", 1),
           0x3: ("SUBD", 2), 0x4: ("ANDA", 1), 0x5: ("BITA", 1),
           0x6: ("LDA", 1), 0x7: ("STA", 1), 0x8: ("EORA", 1),
           0x9: ("ADCA", 1), 0xA: ("ORA", 1), 0xB: ("ADDA", 1),
           0xC: ("CMPX", 2), 0xD: ("JSR", 2), 0xE: ("LDX", 2),
           0xF: ("STX", 2)}

# The $C0-$FF block: accumulator B, plus the 16-bit D/U operations.
BLOCK_B = {0x0: ("SUBB", 1), 0x1: ("CMPB", 1), 0x2: ("SBCB", 1),
           0x3: ("ADDD", 2), 0x4: ("ANDB", 1), 0x5: ("BITB", 1),
           0x6: ("LDB", 1), 0x7: ("STB", 1), 0x8: ("EORB", 1),
           0x9: ("ADCB", 1), 0xA: ("ORB", 1), 0xB: ("ADDB", 1),
           0xC: ("LDD", 2), 0xD: ("STD", 2), 0xE: ("LDU", 2),
           0xF: ("STU", 2)}

BRANCHES = ["BRA", "BRN", "BHI", "BLS", "BCC", "BCS", "BNE", "BEQ",
            "BVC", "BVS", "BPL", "BMI", "BGE", "BLT", "BGT", "BLE"]


def _build():
    table = {}

    # $00-$0F direct, $40-$4F A, $50-$5F B, $60-$6F indexed, $70-$7F extended
    for low, name in UNARY.items():
        table[(0x00 + low,)] = (name, DIRECT)
        table[(0x60 + low,)] = (name, INDEXED)
        table[(0x70 + low,)] = (name, EXTENDED)
        if name != "JMP":                       # there is no JMPA / JMPB
            table[(0x40 + low,)] = (name + "A", INHERENT)
            table[(0x50 + low,)] = (name + "B", INHERENT)

    table.update({
        (0x12,): ("NOP", INHERENT), (0x13,): ("SYNC", INHERENT),
        (0x16,): ("LBRA", REL16), (0x17,): ("LBSR", REL16),
        (0x19,): ("DAA", INHERENT), (0x1A,): ("ORCC", IMM8),
        (0x1C,): ("ANDCC", IMM8), (0x1D,): ("SEX", INHERENT),
        (0x1E,): ("EXG", REGPAIR), (0x1F,): ("TFR", REGPAIR),
        (0x30,): ("LEAX", INDEXED), (0x31,): ("LEAY", INDEXED),
        (0x32,): ("LEAS", INDEXED), (0x33,): ("LEAU", INDEXED),
        (0x34,): ("PSHS", STACK), (0x35,): ("PULS", STACK),
        (0x36,): ("PSHU", STACK), (0x37,): ("PULU", STACK),
        (0x39,): ("RTS", INHERENT), (0x3A,): ("ABX", INHERENT),
        (0x3B,): ("RTI", INHERENT), (0x3C,): ("CWAI", IMM8),
        (0x3D,): ("MUL", INHERENT), (0x3F,): ("SWI", INHERENT),
        (0x8D,): ("BSR", REL8),
    })

    for index, name in enumerate(BRANCHES):
        table[(0x20 + index,)] = (name, REL8)
        if index:                                # $1020 LBRA is not encoded
            table[(0x10, 0x20 + index)] = ("L" + name, REL16)

    for low, (name, width) in BLOCK_A.items():
        immediate = IMM16 if width == 2 else IMM8
        if low not in (0x7, 0xD, 0xF):           # no immediate STA/JSR/STX
            table[(0x80 + low,)] = (name, immediate)
        table[(0x90 + low,)] = (name, DIRECT)
        table[(0xA0 + low,)] = (name, INDEXED)
        table[(0xB0 + low,)] = (name, EXTENDED)

    for low, (name, width) in BLOCK_B.items():
        immediate = IMM16 if width == 2 else IMM8
        if low not in (0x7, 0xD, 0xF):           # no immediate STB/STD/STU
            table[(0xC0 + low,)] = (name, immediate)
        table[(0xD0 + low,)] = (name, DIRECT)
        table[(0xE0 + low,)] = (name, INDEXED)
        table[(0xF0 + low,)] = (name, EXTENDED)

    # Page 1 ($10 xx): the Y and S registers, CMPD, SWI2.
    table[(0x10, 0x3F)] = ("SWI2", INHERENT)
    for low, name, width in ((0x3, "CMPD", 2), (0xC, "CMPY", 2),
                             (0xE, "LDY", 2), (0xF, "STY", 2)):
        if low != 0xF:
            table[(0x10, 0x80 + low)] = (name, IMM16)
        table[(0x10, 0x90 + low)] = (name, DIRECT)
        table[(0x10, 0xA0 + low)] = (name, INDEXED)
        table[(0x10, 0xB0 + low)] = (name, EXTENDED)
    table[(0x10, 0xCE)] = ("LDS", IMM16)
    for high, mode in ((0xD0, DIRECT), (0xE0, INDEXED), (0xF0, EXTENDED)):
        table[(0x10, high + 0xE)] = ("LDS", mode)
        table[(0x10, high + 0xF)] = ("STS", mode)

    # Page 2 ($11 xx): CMPU, CMPS, SWI3.
    table[(0x11, 0x3F)] = ("SWI3", INHERENT)
    for low, name in ((0x3, "CMPU"), (0xC, "CMPS")):
        table[(0x11, 0x80 + low)] = (name, IMM16)
        table[(0x11, 0x90 + low)] = (name, DIRECT)
        table[(0x11, 0xA0 + low)] = (name, INDEXED)
        table[(0x11, 0xB0 + low)] = (name, EXTENDED)
    return table


TABLE = _build()


# Indexed postbyte modes, for postbytes with bit 7 set: extra operand bytes,
# whether the indirect bit (bit 4) is allowed, and the form printed.
#   $x0 ,R+ and $x2 ,-R cannot be indirect: one increment would not be undone.
#   Mode $xF is only ever the extended-indirect form [n16], so it requires the
#   indirect bit; $8F and $CF, with that bit clear, are not 6809 encodings.
INDEXED_MODES = {
    0x0: (0, False, ",{R}+"),   0x1: (0, True, ",{R}++"),
    0x2: (0, False, ",-{R}"),   0x3: (0, True, ",--{R}"),
    0x4: (0, True, ",{R}"),     0x5: (0, True, "B,{R}"),
    0x6: (0, True, "A,{R}"),    0x8: (1, True, "{n},{R}"),
    0x9: (2, True, "{n},{R}"),  0xB: (0, True, "D,{R}"),
    0xC: (1, True, "{n},PCR"),  0xD: (2, True, "{n},PCR"),
    0xF: (2, "required", "[{n}]"),
}


def indexed_extra(postbyte):
    """Extra bytes after an indexed postbyte, or None if it is not a 6809 one."""
    if not postbyte & 0x80:
        return 0                                  # 5-bit signed offset
    entry = INDEXED_MODES.get(postbyte & 0x0F)
    if entry is None:
        return None                               # modes $x7, $xA, $xE
    extra, indirect_allowed, _ = entry
    indirect = bool(postbyte & 0x10)
    if indirect_allowed == "required":
        # Mode $F is the extended-indirect form [n16]. The register bits are
        # ignored by the processor, so $9F and $DF do the same thing, but an
        # assembler only ever emits $9F. Accepting $DF as an instruction means
        # re-assembling it produces $9F and the image changes, so anything but
        # the canonical encoding is data.
        if postbyte != 0x9F:
            return None
    if (postbyte & 0x0F) in (0xC, 0xD):
        # Modes $C and $D are the PC-relative forms, and the same argument as
        # mode $F applies to them: the register bits are ignored by the
        # processor, so $CC and $8C do the same thing - but the operand is
        # written ",PCR" with no register to name, so an assembler can only
        # ever emit the RR=00 encodings ($8C/$9C and $8D/$9D). Accepting $CC
        # as an instruction means re-assembling it produces $8C and the image
        # changes, so anything but the canonical encoding is data.
        #
        # Found in 08904-87011 bank 5, where it cost two bytes of a 16KB
        # rebuild: $4226 held `67 CC 00` and came back as `67 8C 00`, and
        # $55FD held `6E FD 3C 43` and came back as `6E 9D 3C 43`. Both were
        # mis-decodes of data in the first place - which is the point, because
        # a postbyte no assembler emits is evidence the bytes are not code.
        if postbyte & 0x60:
            return None
    if indirect_allowed is False and indirect:
        return None
    return extra


def decode(image, offset):
    """Return (key, mnemonic, mode, length) at offset, or None if undefined."""
    if offset >= len(image):
        return None
    first = image[offset]
    key = (first, image[offset + 1]) if first in (0x10, 0x11) \
        and offset + 1 < len(image) else (first,)
    entry = TABLE.get(key)
    if entry is None:
        return None
    mnemonic, mode = entry
    if mode == REGPAIR:
        # TFR and EXG name two registers in one postbyte. Codes $6, $7 and
        # $C-$F are not registers on a 6809, so a postbyte using one is not a
        # TFR or an EXG at all - those bytes are data, and saying so keeps a
        # disassembler from walking off into them.
        if offset + len(key) >= len(image):
            return None
        postbyte = image[offset + len(key)]
        if (postbyte >> 4) not in REGISTER_CODES or \
                (postbyte & 0x0F) not in REGISTER_CODES:
            return None
    if mode == INDEXED:
        if offset + len(key) >= len(image):
            return None
        extra = indexed_extra(image[offset + len(key)])
        if extra is None:
            return None
        return key, mnemonic, mode, len(key) + 1 + extra
    return key, mnemonic, mode, len(key) + OPERAND_BYTES[mode]


LINE_RE = re.compile(r"^([0-9a-fA-F]{4}):\s+((?:[0-9a-fA-F]{2}\s)+)\s*(.*)$")

# Mnemonics upstream's disassembler prints for opcodes the 6809 does not have,
# and the two 6309 spellings it uses for postbytes $8F and $CF.
# LSLA/LSLB are the same opcodes as ASLA/ASLB - a logical and an arithmetic
# left shift are identical, and both spellings are in the Motorola set. The
# generated listings only ever emit ASL*, so only the unsuffixed LSL was
# here; handwritten source reaches for LSLA when it means "multiply by two",
# and lwasm accepts it, so this assembler has to as well or the two disagree
# on a source file that is perfectly valid.
KNOWN_ALIASES = {"LSL": "ASL", "LSLA": "ASLA", "LSLB": "ASLB",
                 "BHS": "BCC", "BLO": "BCS",
                 "LBHS": "LBCC", "LBLO": "LBCS"}


def check(paths):
    """Hold this table to the shipped listings and report every disagreement."""
    mnemonic_diff = collections.Counter()
    length_diff = collections.Counter()
    undefined = collections.Counter()
    examples = {}
    total = 0

    for path in paths:
        with open(path, errors="replace") as handle:
            for line in handle:
                match = LINE_RE.match(line)
                if not match:
                    continue
                data = bytes(int(b, 16) for b in match.group(2).split())
                printed = match.group(3).split(";")[0].strip()
                if not printed:
                    continue
                total += 1
                result = decode(data, 0)
                if result is None:
                    undefined[data[0]] += 1
                    examples.setdefault(("undef", data[0]), (path, line.rstrip()))
                    continue
                _, mnemonic, mode, length = result
                theirs = printed.split()[0]
                if KNOWN_ALIASES.get(theirs, theirs) != mnemonic:
                    mnemonic_diff[(data[:len(result[0])].hex().upper(),
                                   theirs, mnemonic)] += 1
                    examples.setdefault(("mn", theirs, mnemonic),
                                        (path, line.rstrip()))
                if length != len(data):
                    length_diff[(data[0], len(data), length)] += 1
                    examples.setdefault(("len", data[0], len(data), length),
                                        (path, line.rstrip()))

    print(f"checked {total} decoded lines against the table\n")
    print(f"opcodes this table calls undefined: "
          f"{sum(undefined.values())} line(s), {len(undefined)} distinct")
    for opcode, count in undefined.most_common(12):
        path, line = examples[("undef", opcode)]
        print(f"   ${opcode:02X} x{count:<5} e.g. {line.strip()}")

    print(f"\nmnemonic disagreements: {sum(mnemonic_diff.values())} line(s), "
          f"{len(mnemonic_diff)} distinct")
    for (code, theirs, mine), count in mnemonic_diff.most_common(15):
        print(f"   {code}: listing says {theirs}, table says {mine}  x{count}")

    print(f"\nlength disagreements: {sum(length_diff.values())} line(s), "
          f"{len(length_diff)} distinct")
    for (opcode, theirs, mine), count in length_diff.most_common(15):
        path, line = examples[("len", opcode, theirs, mine)]
        print(f"   ${opcode:02X}: listing {theirs} bytes, table {mine}  x{count}"
              f"   e.g. {line.strip()}")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", nargs="+", metavar="LISTING")
    args = parser.parse_args()
    if args.check:
        return check(args.check)
    print(f"{len(TABLE)} defined opcode keys")
    return 0


if __name__ == "__main__":
    sys.exit(main())
