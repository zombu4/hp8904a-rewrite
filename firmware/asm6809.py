#!/usr/bin/env python3
"""A 6809 assembler for this project's own source. No external toolchain.

    asm6809.py <source.s> -o <image.bin>

Burning an EPROM should not depend on a tool that happens to be installed, so
the assembler that produces the image lives in this repository next to the
disassembler that reads it, and both share one instruction table, mc6809.py.

The pair is checked by round-trip: disassembling each shipped ROM and
assembling the result must reproduce the image byte for byte. That exercises
most of the instruction set against 98,304 bytes of real code, which is why it
catches encoding mistakes. It cannot catch a mistake made identically in both
halves, so when lwasm is present the test suite also assembles the same source
with it and requires the same bytes - corroboration from outside, used when
available and never depended on.

Addressing modes are never chosen by the assembler. The source states them:
`<` forces direct or an 8-bit index offset, `>` forces extended or 16-bit, `#`
is immediate. That is what makes a byte-exact rebuild possible at all, since
guessing a shorter encoding would shift every later address.
"""

import argparse
import os
import re
import sys

from mc6809 import (KNOWN_ALIASES, DIRECT, EXTENDED, IMM8, IMM16, INDEXED, INHERENT, REGPAIR,
                    REL8, REL16, STACK, TABLE)

INDEX_REGISTERS = {"x": 0, "y": 1, "u": 2, "s": 3}
TRANSFER_REGISTERS = {"d": 0x0, "x": 0x1, "y": 0x2, "u": 0x3, "s": 0x4,
                      "pc": 0x5, "a": 0x8, "b": 0x9, "cc": 0xA, "dp": 0xB}
STACK_BITS = {"cc": 0x01, "a": 0x02, "b": 0x04, "dp": 0x08, "x": 0x10,
              "y": 0x20, "u": 0x40, "s": 0x40, "pc": 0x80}
BY_NAME = {}
for key, (name, mode) in TABLE.items():
    BY_NAME.setdefault(name.lower(), {})[mode] = key

# A label starts at column 0. The colon is optional, which is how the equate
# block is written and how hand-written 6809 source normally reads.
# Long branch -> short branch. The pair is exact: same condition, same target,
# same flags, two bytes fewer. Relaxation is therefore semantically free, which
# is why it is the first place to reclaim ROM space from compiler output.
RELAXABLE = {"lbra": "bra", "lbsr": "bsr", "lbhi": "bhi", "lbls": "bls",
             "lbcc": "bcc", "lbcs": "bcs", "lbne": "bne", "lbeq": "beq",
             "lbvc": "bvc", "lbvs": "bvs", "lbpl": "bpl", "lbmi": "bmi",
             "lbge": "bge", "lblt": "blt", "lbgt": "bgt", "lble": "ble",
             "lbrn": "brn"}

# The inverse of RELAXABLE. Shrinking code before a pinned address lengthens
# the distance for anything branching across it, so a branch the compiler
# emitted short can stop reaching and has to be promoted.
LENGTHEN = {short: long for long, short in RELAXABLE.items()}

LABEL_RE = re.compile(r"^([A-Za-z_.][A-Za-z0-9_.]*):?\s*(.*)$")
LINE_RE = re.compile(r"^\s+(\S+)\s*(.*)$")
DIRECTIVES = {"org", "equ", "fcb", "fdb", "fcc", "fill", "end", "rmb"}


class AssemblyError(Exception):
    pass


def strip_comment(text):
    """Remove a trailing comment, respecting fcc's quoted text."""
    out, quote = [], None
    for character in text:
        if quote:
            out.append(character)
            if character == quote:
                quote = None
            continue
        if character == ";":
            break
        # A delimiter opens a string. The apostrophe is deliberately NOT in
        # this set: in `fcb $0D,'A,$0A ; note` it is a character literal, and
        # treating it as an opening delimiter swallowed the rest of the line
        # including the comment.
        #
        # A delimiter opens a string ONLY as the first non-blank character
        # of the operand, which is the only place a string can begin. The
        # condition used to be the opposite - that something non-blank had
        # ALREADY been seen - which was meant to protect the character
        # literal above and instead broke the ordinary case. For `fcc "0" ; note` the
        # leading quote could not open the string, because nothing preceded
        # it; the CLOSING quote then satisfied the condition and opened one
        # instead, so the comment was never stripped and the operand arrived
        # at fcc as `"0" ; note`, whose first and last characters differ:
        # "fcc text must be delimited". Generated listings never write a
        # comment after an fcc, so nothing had ever exercised it; handwritten
        # source writes one on almost every line.
        #
        # Dropping the condition altogether does NOT work, and the byte-exact
        # round-trip caught it at once: `/` is also the division operator, so
        # every `fcb size/2` opened a string and swallowed its own line.
        # a2u12 stopped reassembling to its image while the four A2U13 pages
        # still did - which is why the control runs over all five.
        if character in "\"/|~" and not "".join(out).strip():
            quote = character
        out.append(character)
    return "".join(out).strip()


class Assembler:
    def __init__(self, relax=False):
        self.symbols = {}
        self.lines = []
        self.here = 0               # the address being assembled, for `*`
        self.macros = {}            # name -> [(label, mnemonic, operand)]
        self.macro_name = None      # the macro currently being defined
        self.relax = relax
        self.shortened = set()      # long branches assembled short
        self.lengthened = set()     # short branches promoted to long

    # -- expressions ------------------------------------------------------
    def value(self, text, where):
        """Evaluate an operand expression.

        Sums are supported so that a reference into the middle of a block can
        be written as `block+4` rather than as the address it happens to have
        today. The compiler emitted several of those as bare numbers, and a
        bare number does not follow the block when the code before it shrinks.
        """
        text = text.strip()
        if not text:
            raise AssemblyError(f"{where}: empty expression")

        # `*` on its own is the address being assembled, which is how a
        # source says "pad from here to there" without knowing how long the
        # code before it turned out to be:
        #
        #     fill $FF,ABI_BASE-*
        #
        # It has to be tested BEFORE the multiplication split below, or that
        # split sees a bare `*`, produces two empty pieces and reports an
        # empty expression - which is what it did.
        if text == "*":
            return self.here

        # Bitwise operators, lowest precedence first. Generated listings never
        # used them - the disassembler emits every constant already folded -
        # so the evaluator only ever needed + and -. Handwritten source uses
        # them constantly: `IRQ_MASK|FIRQ_MASK` says which two bits and why,
        # where $50 says neither. lwasm evaluates them, this did not, and the
        # two assemblers disagreeing on a source file is exactly what the
        # cross-check exists to catch.
        #
        # Precedence is | then ^ then &, matching C and lwasm. Splitting on
        # the lowest-precedence operator first and recursing gives that
        # without a parser.
        for operator, apply in (("|", lambda a, b: a | b),
                                ("^", lambda a, b: a ^ b),
                                ("&", lambda a, b: a & b)):
            pieces = text.split(operator)
            if len(pieces) > 1:
                total = self.value(pieces[0], where)
                for piece in pieces[1:]:
                    total = apply(total, self.value(piece, where))
                return total

        # A leading ~ complements the rest, so a mask can be written as the
        # bits it clears: `andcc #~BOTH_MASKS` rather than #$AF.
        if text.startswith("~"):
            return (~self.value(text[1:], where)) & 0xFFFF

        # Split on + and - that join terms, leaving a leading sign alone.
        parts = re.split(r"(?<=[^\s+\-])\s*([+\-])\s*", text)
        if len(parts) == 1:
            # No addition here, so this is where * and / bind - tighter than
            # + and -, as in every assembler and every language. They were
            # not supported at all: generated listings emit constants already
            # folded, so nothing had written one. Handwritten source does
            # immediately - ABI_BASE+3*ABI_SLOT says what a jump-table slot
            # IS, where a hand-computed $F009 says nothing and goes wrong the
            # moment the table changes.
            for operator in ("*", "/"):
                pieces = text.split(operator)
                # An empty piece means this was not a binary operator at all -
                # a bare `*` for the current address, or a stray one. Leave it
                # to term() to report rather than splitting nothing in half.
                if len(pieces) > 1 and all(p.strip() for p in pieces):
                    total = self.value(pieces[0], where)
                    for piece in pieces[1:]:
                        other = self.value(piece, where)
                        if operator == "/":
                            if other == 0:
                                raise AssemblyError(
                                    f"{where}: division by zero in '{text}'")
                            total //= other
                        else:
                            total *= other
                    return total & 0xFFFF
        if len(parts) > 1:
            # Each operand goes back through value(), not straight to term():
            # that is what lets a higher-precedence operator inside one of
            # them be seen at all. With term() here, `BASE+3*SLOT` split into
            # 'BASE', '+', '3*SLOT' and the multiplicative branch below was
            # unreachable - it only ever ran for an expression with no + or -
            # in it, which is the one case that did not need it.
            total = self.value(parts[0], where)
            for index in range(1, len(parts) - 1, 2):
                piece = self.value(parts[index + 1], where)
                total = total + piece if parts[index] == "+" else total - piece
            return total
        return self.term(text, where)

    def term(self, text, where):
        text = text.strip()
        if not text:
            raise AssemblyError(f"{where}: empty expression")
        negate = False
        if text.startswith("-"):
            negate, text = True, text[1:]
        if text.startswith("'") and len(text) >= 2:
            return ord(text[1])          # 'A character literal
        if text.startswith("$"):
            result = int(text[1:], 16)
        elif text.startswith("%"):
            result = int(text[1:], 2)
        elif re.fullmatch(r"\d+", text):
            result = int(text, 10)
        elif text in self.symbols:
            result = self.symbols[text]
        else:
            raise AssemblyError(f"{where}: undefined symbol '{text}'")
        return -result if negate else result

    # -- operand encoding -------------------------------------------------
    def indexed(self, operand, where, address, length_hint):
        """Return (postbyte, extra bytes) for one indexed operand."""
        text = operand.strip()
        indirect = text.startswith("[") and text.endswith("]")
        if indirect:
            text = text[1:-1].strip()

        if "," not in text:                       # [$1234] extended indirect
            if not indirect:
                raise AssemblyError(f"{where}: indexed operand without a comma")
            forced = text.lstrip("<>")
            return 0x9F, [self.value(forced, where) >> 8 & 0xFF,
                          self.value(forced, where) & 0xFF]

        offset_text, _, register_text = text.rpartition(",")
        register_text = register_text.strip().lower()
        offset_text = offset_text.strip()

        if register_text == "pcr":
            if not offset_text[:1] in ("<", ">"):
                raise AssemblyError(f"{where}: pcr offset must force its width")
            wide = offset_text[0] == ">"
            target = self.value(offset_text[1:], where)
            # The offset is measured from the address of the next
            # instruction, so it counts the opcode, the postbyte and the
            # offset bytes themselves.
            size = 2 if wide else 1
            following = address + length_hint + 1 + size
            displacement = (target - following) & 0xFFFF
            postbyte = (0x8D if wide else 0x8C) | (0x10 if indirect else 0)
            if wide:
                return postbyte, [displacement >> 8 & 0xFF, displacement & 0xFF]
            signed = displacement - 0x10000 if displacement > 0x7FFF else displacement
            if not -128 <= signed <= 127:
                raise AssemblyError(f"{where}: pcr offset {signed} does not fit "
                                    f"in one byte")
            return postbyte, [signed & 0xFF]

        auto = 0
        while register_text.startswith("-"):
            auto -= 1
            register_text = register_text[1:]
        while register_text.endswith("+"):
            auto += 1
            register_text = register_text[:-1]
        if register_text not in INDEX_REGISTERS:
            raise AssemblyError(f"{where}: '{register_text}' is not an index "
                                f"register")
        bits = INDEX_REGISTERS[register_text] << 5

        if auto:
            codes = {1: 0x80, 2: 0x81, -1: 0x82, -2: 0x83}
            if auto not in codes or offset_text:
                raise AssemblyError(f"{where}: bad auto-increment operand")
            postbyte = 0x80 | bits | (codes[auto] & 0x0F)
            if indirect:
                if auto in (1, -1):
                    raise AssemblyError(f"{where}: ,R+ and ,-R cannot be "
                                        f"indirect")
                postbyte |= 0x10
            return postbyte, []

        if offset_text.lower() in ("a", "b", "d"):
            codes = {"a": 0x6, "b": 0x5, "d": 0xB}
            postbyte = 0x80 | bits | codes[offset_text.lower()]
            return postbyte | (0x10 if indirect else 0), []

        if not offset_text:                        # ,R
            return 0x80 | bits | 0x4 | (0x10 if indirect else 0), []

        if offset_text[0] in "<>":
            wide = offset_text[0] == ">"
            number = self.value(offset_text[1:], where)
            postbyte = 0x80 | bits | (0x9 if wide else 0x8) \
                | (0x10 if indirect else 0)
            if wide:
                return postbyte, [number >> 8 & 0xFF, number & 0xFF]
            return postbyte, [number & 0xFF]

        number = self.value(offset_text, where)
        # An unprefixed offset takes the SMALLEST form it fits in: 5-bit if
        # it can, 8-bit if not, 16-bit beyond that. The disassembler always
        # writes < or > to say which it wants, so this only ever saw offsets
        # that already fitted - and handwritten source writes `ldb 22,x`
        # without wanting to know that 22 needs the wider form. lwasm chooses
        # for you, and refusing here made the two assemblers disagree on
        # source that is perfectly valid.
        if indirect or not -16 <= number <= 15:
            if -128 <= number <= 127:
                postbyte = 0x80 | bits | 0x8 | (0x10 if indirect else 0)
                return postbyte, [number & 0xFF]
            postbyte = 0x80 | bits | 0x9 | (0x10 if indirect else 0)
            return postbyte, [(number >> 8) & 0xFF, number & 0xFF]
        return bits | (number & 0x1F), []

    def indexed_size(self, operand, where):
        """Size of the postbyte plus its extra bytes, without needing labels."""
        text = operand.strip()
        if text.startswith("["):
            text = text[1:-1].strip()
        if "," not in text:
            return 3
        offset_text, _, register_text = text.rpartition(",")
        offset_text = offset_text.strip()
        if offset_text[:1] == "<":
            return 2
        if offset_text[:1] == ">":
            return 3
        if not offset_text:
            return 1                    # ,R - the postbyte says it all
        if offset_text.strip().lower() in ("a", "b", "d"):
            return 1                    # accumulator offset

        # An unprefixed offset takes the smallest form it FITS in, and this
        # has to agree with what encode() actually emits. It did not: this
        # returned 1 unconditionally, assuming the 5-bit form, while the
        # encoder promotes anything outside -16..15 to an 8- or 16-bit
        # offset. So `ldb 22,x` was SIZED at two bytes and EMITTED as three.
        #
        # The effect was quiet and nasty. The bytes came out right, but every
        # label after such an instruction was recorded two bytes low, so an
        # `fdb` of a handler pointed two bytes short of it and a BRA
        # displacement landed two bytes early - a jump into the middle of an
        # instruction on real hardware. It only showed because the second
        # assembler disagreed.
        #
        # A label may not be known on the first round; the assembler now
        # iterates to a fixpoint, so guessing the middle width and letting it
        # settle is safe.
        try:
            number = self.value(offset_text, where)
        except AssemblyError:
            return 2
        if -16 <= number <= 15:
            return 1
        if -128 <= number <= 127:
            return 2
        return 3

    def mode_of(self, mnemonic, operand, where):
        """Which addressing mode this line uses. The source is explicit."""
        modes = BY_NAME.get(mnemonic)
        if modes is None:
            raise AssemblyError(f"{where}: unknown mnemonic '{mnemonic}'")
        if REL8 in modes:
            return REL8
        if REL16 in modes:
            return REL16
        if not operand:
            if INHERENT not in modes:
                raise AssemblyError(f"{where}: '{mnemonic}' needs an operand")
            return INHERENT
        if REGPAIR in modes:
            return REGPAIR
        if STACK in modes:
            return STACK
        if operand.startswith("#"):
            for candidate in (IMM16, IMM8):
                if candidate in modes:
                    return candidate
            raise AssemblyError(f"{where}: '{mnemonic}' has no immediate form")
        # Indexed is decided before direct and extended, because an indexed
        # operand also carries < or > to force its offset width: `<$21,x` is
        # indexed with an 8-bit offset, `<$21` is direct.
        if INDEXED in modes and ("," in operand or operand.startswith("[")):
            return INDEXED
        # `<` and `>` force a width, but only for an instruction that has that
        # form. CWAI is immediate-only, so `cwai <$42` asked for a direct mode
        # that does not exist and came back as a KeyError from the table
        # lookup rather than as something a person can read.
        if operand.startswith("<"):
            if DIRECT not in modes:
                raise AssemblyError(f"{where}: '{mnemonic}' has no direct form")
            return DIRECT
        if operand.startswith(">"):
            if EXTENDED not in modes:
                raise AssemblyError(f"{where}: '{mnemonic}' has no extended "
                                    f"form")
            return EXTENDED
        if EXTENDED in modes:
            return EXTENDED
        raise AssemblyError(f"{where}: cannot tell the addressing mode of "
                            f"'{mnemonic} {operand}'")

    def size_of(self, mnemonic, operand, where):
        mode = self.mode_of(mnemonic, operand, where)
        key = BY_NAME[mnemonic][mode]
        base = len(key)
        if mode == INHERENT:
            return base
        if mode in (IMM8, DIRECT, REL8, REGPAIR, STACK):
            return base + 1
        if mode in (IMM16, EXTENDED, REL16):
            return base + 2
        return base + self.indexed_size(operand, where)

    def encode(self, mnemonic, operand, where, address):
        mode = self.mode_of(mnemonic, operand, where)
        key = BY_NAME[mnemonic][mode]
        out = list(key)
        if mode == INHERENT:
            return out
        if mode == IMM8:
            return out + [self.value(operand[1:], where) & 0xFF]
        if mode == IMM16:
            number = self.value(operand[1:], where)
            return out + [number >> 8 & 0xFF, number & 0xFF]
        if mode == DIRECT:
            return out + [self.value(operand[1:], where) & 0xFF]
        if mode == EXTENDED:
            number = self.value(operand.lstrip(">"), where)
            return out + [number >> 8 & 0xFF, number & 0xFF]
        if mode in (REL8, REL16):
            target = self.value(operand, where)
            size = len(out) + (1 if mode == REL8 else 2)
            displacement = (target - (address + size)) & 0xFFFF
            if mode == REL8:
                signed = displacement - 0x10000 if displacement > 0x7FFF \
                    else displacement
                if not -128 <= signed <= 127:
                    raise AssemblyError(f"{where}: branch to ${target:04X} is "
                                        f"{signed} away, too far for a short "
                                        f"branch")
                return out + [signed & 0xFF]
            return out + [displacement >> 8 & 0xFF, displacement & 0xFF]
        if mode == REGPAIR:
            first, _, second = operand.partition(",")
            for name in (first.strip().lower(), second.strip().lower()):
                if name not in TRANSFER_REGISTERS:
                    raise AssemblyError(f"{where}: '{name}' is not a register")
            return out + [TRANSFER_REGISTERS[first.strip().lower()] << 4
                          | TRANSFER_REGISTERS[second.strip().lower()]]
        if mode == STACK:
            if operand.startswith("#"):
                return out + [self.value(operand[1:], where) & 0xFF]
            postbyte = 0
            for name in operand.split(","):
                name = name.strip().lower()
                # D is A and B together, and PSHS D is the ordinary way to
                # save the accumulator. The table lists the two halves and
                # not the pair, because the disassembler always writes them
                # separately - so `pshs d`, which lwasm assembles and which
                # handwritten source uses constantly, was refused here.
                if name == "d":
                    postbyte |= STACK_BITS["a"] | STACK_BITS["b"]
                    continue
                if name not in STACK_BITS:
                    raise AssemblyError(f"{where}: '{name}' cannot be stacked")
                if name == "u" and mnemonic in ("pshu", "pulu"):
                    raise AssemblyError(f"{where}: {mnemonic} stacks S, not U")
                if name == "s" and mnemonic in ("pshs", "puls"):
                    raise AssemblyError(f"{where}: {mnemonic} stacks U, not S")
                postbyte |= STACK_BITS[name]
            return out + [postbyte]
        postbyte, extra = self.indexed(operand, where, address, len(key))
        return out + [postbyte] + extra

    # -- data directives --------------------------------------------------
    def data_size(self, directive, operand, where):
        if directive == "fcb":
            return len([p for p in operand.split(",") if p.strip()])
        if directive == "fdb":
            return 2 * len([p for p in operand.split(",") if p.strip()])
        if directive == "fcc":
            return len(self.text_of(operand, where))
        if directive == "fill":
            _, _, count = operand.partition(",")
            return self.value(count, where)
        if directive == "rmb":
            return self.value(operand, where)
        return 0

    def text_of(self, operand, where):
        operand = operand.strip()
        if len(operand) < 2 or operand[0] != operand[-1]:
            raise AssemblyError(f"{where}: fcc text must be delimited")
        return operand[1:-1]

    def data_bytes(self, directive, operand, where):
        if directive == "fcb":
            return [self.value(p, where) & 0xFF
                    for p in operand.split(",") if p.strip()]
        if directive == "fdb":
            out = []
            for part in operand.split(","):
                if not part.strip():
                    continue
                number = self.value(part, where)
                out += [number >> 8 & 0xFF, number & 0xFF]
            return out
        if directive == "fcc":
            return [ord(c) for c in self.text_of(operand, where)]
        if directive == "fill":
            value, _, count = operand.partition(",")
            return [self.value(value, where) & 0xFF] * self.value(count, where)
        if directive == "rmb":
            return [0] * self.value(operand, where)
        return []

    # -- passes -----------------------------------------------------------
    def parse(self, path, stack=None):
        """Read one source file, following `include` into others.

        The assembler had no include: the only sources were single generated
        listings, so a source TREE could not be assembled at all. A rewrite
        into handwritten assembly needs one - nobody hand-maintains a 23,000
        line file - so this follows `include "path"` relative to the including
        file, which is what every assembler does and what a reader expects.

        `stack` carries the chain of files currently open. A file that
        includes itself, directly or through others, would otherwise be read
        until the process died; here it is refused with the cycle spelled out.
        """
        stack = list(stack or [])
        full = os.path.abspath(path)
        if full in stack:
            chain = " -> ".join(os.path.basename(p) for p in stack + [full])
            raise AssemblyError(f"{path}: include cycle: {chain}")
        stack.append(full)
        with open(path) as handle:
            for number, raw in enumerate(handle, 1):
                where = f"{path}:{number}"
                stripped = raw.strip()
                if stripped.lower().startswith("include"):
                    target = stripped[7:].strip().strip('"\'')
                    if not target:
                        raise AssemblyError(f"{where}: include with no file")
                    nested = os.path.join(os.path.dirname(full), target)
                    if not os.path.exists(nested):
                        raise AssemblyError(
                            f"{where}: include '{target}' does not exist "
                            f"(looked in {os.path.dirname(full) or '.'})")
                    self.parse(nested, stack)
                    continue
                text = raw.rstrip("\n")
                if not text.strip() or text.lstrip().startswith(";"):
                    continue
                label = None
                match = LABEL_RE.match(text)
                if match:
                    label, rest = match.group(1), match.group(2)
                    # A label may be followed by nothing but a comment:
                    #
                    #   mul16_no_carry_2      ; middle products can carry
                    #
                    # Stripping the label left "; middle products..." behind,
                    # which then parsed as a mnemonic of ';'. Generated
                    # listings put a label on its own line and the comment
                    # above it, so nothing had ever produced this shape.
                    if rest.strip().startswith(";"):
                        rest = ""
                    text = "        " + rest if rest.strip() else ""
                if text.strip():
                    inner = LINE_RE.match(text)
                    if not inner:
                        raise AssemblyError(f"{where}: cannot parse '{raw.strip()}'")
                    mnemonic = inner.group(1).lower()
                    # Fold a Motorola alias to the canonical spelling here,
                    # once, so nothing downstream has to know about them:
                    # LSLA is ASLA, BHS is BCC. mc6809.py has carried the
                    # table all along and this never consulted it, so source
                    # both assemblers should accept was rejected by one.
                    # Generated listings only emit the canonical form, which
                    # is why nothing had ever hit it.
                    mnemonic = KNOWN_ALIASES.get(mnemonic.upper(),
                                                 mnemonic.upper()).lower()
                    operand = strip_comment(inner.group(2))
                else:
                    mnemonic, operand = None, ""
                # --- macro definition and expansion --------------------
                #
                # lwasm has macros; this did not, because a generated listing
                # never contains one. Handwritten source does: the whole
                # point of DISABLE_INTERRUPTS is that the reader sees why the
                # interrupts are off, and a macro is how that becomes two
                # instructions with no call overhead.
                #
                # Deliberately simple, and it says so rather than pretending
                # otherwise: positional parameters \1 to \9, no nesting, no
                # conditionals, no local labels inside a macro. That covers
                # what this firmware needs and nothing more. A macro that
                # defines a label would define it twice on the second use, so
                # the ones here emit instructions only.
                if mnemonic == "macro":
                    if label is None:
                        raise AssemblyError(f"{where}: macro without a name")
                    # Mnemonics are lowercased at parse time, so the name is
                    # folded here too - otherwise a macro written MASK is
                    # stored as "MASK" and the "mask" that comes back never
                    # matches it.
                    self.macro_name = label.lower()
                    self.macros[self.macro_name] = []
                    continue
                if mnemonic == "endm":
                    if self.macro_name is None:
                        raise AssemblyError(f"{where}: endm with no macro")
                    self.macro_name = None
                    continue
                if self.macro_name is not None:
                    # Inside a definition: remember the line, do not assemble
                    # it. The label is kept so a macro body can carry one,
                    # even though nothing here uses that yet.
                    self.macros[self.macro_name].append(
                        (label, mnemonic, operand))
                    continue
                if mnemonic in self.macros:
                    arguments = [a.strip() for a in operand.split(",")] \
                        if operand.strip() else []
                    for index, (inner_label, inner_mnemonic,
                                inner_operand) in enumerate(
                                    self.macros[mnemonic]):
                        expanded = inner_operand
                        for number, argument in enumerate(arguments, 1):
                            expanded = expanded.replace(f"\\{number}",
                                                        argument)
                        # The invocation's own "path:line" is kept exactly.
                        # Appending " in macro NAME" to it broke code that
                        # parses a location back into a line number, with an
                        # error naming the macro rather than the line - a
                        # long way from the source of it.
                        self.lines.append(
                            (where, inner_label, inner_mnemonic, expanded))
                    continue

                self.lines.append((where, label, mnemonic, operand))

    def first_pass(self):
        self.origin = None
        address = 0
        for index, (where, label, mnemonic, operand) in enumerate(self.lines):
            # `*` IS THE ADDRESS OF THIS LINE, AND IT IS SET HERE FOR EVERY
            # LINE. It used to be assigned in two places further down - the
            # org branch and the DIRECTIVES branch - which left it stale for
            # the three kinds of line that never reached them:
            #
            #   an equ, because that branch is below this point and continues,
            #   so `*` read whatever the previous data directive had left;
            #   an instruction, which assigned it nowhere at all;
            #   and every line in second_pass, which never assigned it, so the
            #   pass that emits the bytes ran with whatever first_pass ended on.
            #
            # The last of those lost bytes in silence: `fill $FF,$8010-*` with
            # a stale `*` computes a NEGATIVE count, and [value] * negative is
            # the empty list, so the image came out short with no diagnostic.
            # test/star_selftest.py holds all four shapes.
            self.here = address
            if mnemonic == "equ":
                if label is None:
                    raise AssemblyError(f"{where}: equ without a label")
                # An equ may not redefine an existing name, and that includes
                # redefining it to the same value. lwasm refuses both, and
                # this did not refuse either - so a constant defined in two
                # files assembled here and failed there, which is a
                # disagreement about what is VALID rather than about what the
                # bytes are. Two assemblers that disagree on validity are not
                # checking each other; the one that accepts more is simply
                # quieter.
                #
                # This was found by CHANNEL_MAX, declared in both
                # modules/scratch.inc and modules/channel.s as 4. Same value,
                # so nothing was wrong with the output - but the next such
                # pair would not have been.
                #
                # The label branch below already refused a redefinition. Only
                # this half was unguarded, which is the shape the standing
                # rule about fixing the class rather than the instance names.
                if label in self.symbols:
                    raise AssemblyError(
                        f"{where}: '{label}' defined twice "
                        f"(already ${self.symbols[label]:04X})")
                self.symbols[label] = self.value(operand, where)
                continue
            if label is not None:
                if label in self.symbols:
                    raise AssemblyError(f"{where}: '{label}' defined twice")
                self.symbols[label] = address
            if mnemonic is None:
                continue
            if mnemonic == "org":
                address = self.value(operand, where)
            elif mnemonic == "end":
                break
            elif mnemonic in DIRECTIVES:
                address += self.data_size(mnemonic, operand, where)
            else:
                if index in self.shortened:
                    address += self.size_of(RELAXABLE[mnemonic], operand, where)
                elif index in self.lengthened:
                    address += self.size_of(LENGTHEN[mnemonic], operand, where)
                else:
                    address += self.size_of(mnemonic, operand, where)

    def relax_branches(self):
        """Shorten every long branch whose target is within reach.

        Shortening one branch moves everything after it, which can bring
        another branch into range, so this repeats until nothing more changes.

        It cannot only shorten. A pinned org holds an address fixed, so code
        shrinking before a pin does not move code after it, and a branch that
        crosses the pin gets further away rather than closer. So each pass both
        shortens what now fits and lengthens what no longer does, and gives up
        rather than oscillating for ever.
        """
        for _ in range(32):
            self.symbols = {}
            self.first_pass()
            address, changed = 0, False
            for index, (where, label, mnemonic, operand) in \
                    enumerate(self.lines):
                if mnemonic == "org":
                    address = self.value(operand, where)
                    continue
                if mnemonic in (None, "equ", "end"):
                    continue
                if mnemonic in DIRECTIVES:
                    address += self.data_size(mnemonic, operand, where)
                    continue
                short = index in self.shortened
                name = RELAXABLE[mnemonic] if short else mnemonic
                size = self.size_of(name, operand, where)
                if mnemonic in RELAXABLE:
                    try:
                        target = self.value(operand, where)
                    except AssemblyError:
                        target = None
                    if target is not None:
                        displacement = target - (address + 2)
                        fits = -128 <= displacement <= 127
                        if fits and not short:
                            self.shortened.add(index)
                            changed = True
                        elif short and not fits:
                            self.shortened.discard(index)
                            changed = True
                address += size
            if not changed:
                break
        else:
            raise AssemblyError("branch relaxation did not settle after 32 "
                                "passes; a branch is oscillating between "
                                "short and long across a pinned address")
        # Convergence is not proof. Walk the final layout once more and
        # un-shorten anything that does not actually fit, repeating until a
        # pass finds nothing, so no branch can reach the encoder too far.
        for _ in range(32):
            self.symbols = {}
            self.first_pass()
            address, bad = 0, False
            for index, (where, label, mnemonic, operand) in \
                    enumerate(self.lines):
                if mnemonic == "org":
                    address = self.value(operand, where)
                    continue
                if mnemonic in (None, "equ", "end"):
                    continue
                if mnemonic in DIRECTIVES:
                    address += self.data_size(mnemonic, operand, where)
                    continue
                if index in self.shortened:
                    try:
                        target = self.value(operand, where)
                    except AssemblyError:
                        target = None
                    if target is not None and \
                            not -128 <= target - (address + 2) <= 127:
                        self.shortened.discard(index)
                        bad = True
                    address += self.size_of(
                        RELAXABLE[mnemonic] if index in self.shortened
                        else mnemonic, operand, where)
                else:
                    address += self.size_of(mnemonic, operand, where)
            if not bad:
                break
        else:
            raise AssemblyError("branch relaxation would not settle")

        # ITERATE TO A FIXPOINT, not twice.
        #
        # Two passes are enough only while every instruction's size is known
        # from its text alone. That stopped being true when unprefixed
        # indexed offsets started choosing their own width: `ldb count,x`
        # is two bytes if count fits five bits and three if it does not, so
        # a symbol's VALUE now decides a SIZE, and a size decides the
        # addresses of everything after it - which decides other symbols.
        #
        # The symptom was ugly and quiet: the emitted image disagreed with
        # this assembler's OWN map by two bytes, and an `fdb` of a
        # forward-declared handler pointed two bytes short of the routine.
        # Nothing crashed. It would have been a jump into the middle of an
        # instruction on real hardware.
        #
        # Repeating until the symbol table stops moving is what a real
        # assembler does. It converges in two or three rounds here; the cap
        # is a backstop against a source that oscillates, and it says so
        # rather than silently emitting whatever the last round produced.
        previous = None
        for round_number in range(10):
            self.symbols = {}
            self.first_pass()
            if self.symbols == previous:
                return
            previous = dict(self.symbols)
        raise AssemblyError(
            "the symbol table did not settle after 10 passes: an instruction "
            "size depends on a value that depends on that size")

    def second_pass(self, pad=0xFF):
        memory, address, lowest, highest = {}, 0, None, None
        self.reclaimed = 0
        self.emitted = []
        self.origin = None
        self.gaps = []
        self.retry = False
        for index, (where, label, mnemonic, operand) in enumerate(self.lines):
            self.here = address         # `*`, maintained here as well: this
                                        # is the pass that emits the bytes,
                                        # and it used to run with whatever
                                        # first_pass happened to finish on
            if mnemonic in (None, "equ"):
                continue
            if mnemonic == "org":
                target = self.value(operand, where)
                # A forward org leaves a gap. Fill it rather than leaving
                # addresses unwritten, because an unwritten byte burns as $00
                # and $00 is a legal opcode. The gap is the space reclaimed.
                # Only the first org may move the address anywhere: it sets
                # the origin. After that an org may only move forward. A
                # backward one relocates the whole image - the origin
                # changes, every byte lands at the wrong address, and the
                # reset vector is fetched from the wrong word. That burns a
                # brick, so it is refused. The check belongs here rather than
                # in first_pass: relaxation starts with every branch long and
                # shrinks over successive passes, so an intermediate layout
                # can overrun a pin that the settled one clears.
                if lowest is not None and target < address:
                    raise AssemblyError(
                        f"{where}: org ${target:04X} goes backwards from "
                        f"${address:04X}. An org may only move forward once "
                        f"the origin is set; going back would overlay bytes "
                        f"already placed and shift the image")
                if lowest is not None and target > address:
                    for gap in range(address, target):
                        # The same guard the instruction path uses. Without
                        # it a gap fill quietly replaces bytes the source
                        # already declared, and --balance can then pick one
                        # of those addresses as padding to adjust.
                        if gap in memory:
                            raise AssemblyError(
                                f"{where}: filling the gap to ${target:04X} "
                                f"would overwrite ${gap:04X}, which is "
                                f"already written")
                        memory[gap] = pad
                        highest = max(highest, gap)
                    self.gaps.append((address, target - 1))
                    self.reclaimed += target - address
                address = target
                continue
            if mnemonic == "end":
                break
            if mnemonic in DIRECTIVES:
                data = self.data_bytes(mnemonic, operand, where)
            elif index in self.lengthened:
                data = self.encode(LENGTHEN[mnemonic], operand, where, address)
            elif index in self.shortened:
                try:
                    data = self.encode(RELAXABLE[mnemonic], operand, where,
                                       address)
                except AssemblyError:
                    # The encoder is the only authority on whether a branch
                    # fits. Anything the layout walk got wrong shows up here,
                    # so this un-shortens and asks to be run again rather than
                    # emitting a branch that does not reach.
                    self.shortened.discard(index)
                    self.retry = True
                    data = self.encode(mnemonic, operand, where, address)
            else:
                try:
                    data = self.encode(mnemonic, operand, where, address)
                except AssemblyError:
                    if mnemonic not in LENGTHEN:
                        raise
                    self.lengthened.add(index)
                    self.retry = True
                    data = self.encode(LENGTHEN[mnemonic], operand, where,
                                       address)
            name = mnemonic
            if index in self.shortened:
                name = RELAXABLE[mnemonic]
            elif index in self.lengthened:
                name = LENGTHEN[mnemonic]
            # `index` counts parsed lines, not source lines - blanks and
            # comments never reach self.lines - so the map records the real
            # source line taken from `where`. A consumer that correlates the
            # map with the source file needs the number the editor shows.
            self.emitted.append((int(where.rsplit(":", 1)[1]), address,
                                 len(data), name, operand))
            for byte in data:
                if address in memory:
                    raise AssemblyError(f"{where}: ${address:04X} written twice")
                memory[address] = byte & 0xFF
                lowest = address if lowest is None else min(lowest, address)
                highest = address if highest is None else max(highest, address)
                address += 1
        if lowest is None:
            raise AssemblyError("nothing was assembled")
        missing = [a for a in range(lowest, highest + 1) if a not in memory]
        if missing:
            raise AssemblyError(f"{len(missing)} address(es) never written, "
                                f"first ${missing[0]:04X}; a gap would burn "
                                f"as $00")
        return bytes(memory[a] for a in range(lowest, highest + 1)), lowest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source")
    parser.add_argument("-o", "--output", required=True)
    parser.add_argument("--relax", action="store_true",
                        help="shorten long branches that are within reach")
    parser.add_argument("--balance", help="adjust one padding byte so the "
                                          "ADCB self-test returns this value, "
                                          "hex: 0 for A2U12, the page number "
                                          "for an A2U13 page")
    parser.add_argument("--size", help="pad the output to this many bytes, "
                                       "hex, so a shrunken image still fills "
                                       "its ROM")
    parser.add_argument("--export", help="write every label and its address, "
                                         "for another image to import")
    parser.add_argument("--import", dest="imports", action="append", default=[],
                        help="read labels exported from another image and "
                             "define them as equates")
    parser.add_argument("--map", help="write a line-by-line map of what each "
                                      "source line assembled to")
    parser.add_argument("--pad", default="FF",
                        help="byte used to fill a gap left by a forward org")
    args = parser.parse_args()

    worker = Assembler(relax=args.relax)
    try:
        for path in args.imports:
            # Labels exported from another ROM. The A2U13 pages call into
            # A2U12 by absolute address, so if either is rebuilt the other has
            # to be told where those routines ended up.
            with open(path) as handle:
                for line in handle:
                    parts = line.split()
                    if len(parts) == 2:
                        worker.symbols[parts[0]] = int(parts[1], 16)
        worker.parse(args.source)
        if args.relax:
            worker.relax_branches()
        else:
            worker.first_pass()
        for _ in range(16):
            image, origin = worker.second_pass(pad=int(args.pad, 16))
            if not worker.retry:
                break
            worker.symbols = {}
            worker.first_pass()
        else:
            raise AssemblyError("branch relaxation would not settle")
    except AssemblyError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    if args.size:
        want = int(args.size, 16)
        if len(image) > want:
            print(f"error: {len(image)} bytes will not fit in {want}",
                  file=sys.stderr)
            return 1
        unpadded = len(image)
        image = image + bytes([int(args.pad, 16)]) * (want - len(image))

    if args.balance is not None:
        # The ROM self-test adds every byte with the carry from the previous
        # CMPX, which is set for all but the first byte. So the result is
        # (sum + len - 1) mod 256, and one padding byte can be adjusted to
        # make it whatever the test expects. It has to be padding: changing a
        # byte of code or data to fix a checksum would be a very quiet bug.
        want = int(args.balance, 16)
        gaps = list(worker.gaps)
        # The tail left by --size is padding too, and often the largest run
        # of it. It has to be measured before the padding is appended: once
        # image has been padded its length already equals the target, so a
        # test of len(image) against that target can never be true and the
        # tail is silently never offered.
        if args.size and unpadded < int(args.size, 16):
            gaps.append((origin + unpadded, origin + int(args.size, 16) - 1))
        data = bytearray(image)
        if not gaps:
            print("error: nothing to balance with; no padding was produced",
                  file=sys.stderr)
            return 1
        low, high = max(gaps, key=lambda pair: pair[1] - pair[0])
        # The FIRST byte of the gap, not the last. Every large gap in this
        # image is preceded by an RTS, so nothing falls into it; the byte
        # after it is the next routine's entry point, and that is an address
        # something branches to. Putting the adjustable byte at the far end
        # puts it immediately before a live entry point, where an off-by-one
        # branch would land on it. At the near end its neighbour is the RTS
        # that nothing continues past. Both are safe in this image and the
        # near end is safe for a weaker reason, which is the one to prefer.
        place = low - origin
        # The whole point is that only padding is adjusted. Check it rather
        # than trust the bookkeeping: if a gap record is ever wrong, this is
        # the difference between a corrected checksum and a corrupted byte of
        # code that still passes the self-test.
        pad_byte = int(args.pad, 16)
        if not 0 <= place < len(data) or data[place] != pad_byte:
            found = f"${data[place]:02X}" if 0 <= place < len(data) else "off the end"
            print(f"error: ${origin + place:04X} is not a padding byte "
                  f"(found {found}, expected ${pad_byte:02X}); refusing to "
                  f"balance the checksum by changing it", file=sys.stderr)
            return 1
        # And it must be padding for its whole neighbourhood, not just at the
        # one byte: a gap record that is off by a little would otherwise let
        # this land one byte inside real code and still pass the test above.
        run = 0
        while (place + run < len(data) and data[place + run] == pad_byte
               and origin + place + run <= high):
            run += 1
        if run < 4:
            print(f"error: ${origin + place:04X} starts a run of only {run} "
                  f"padding byte(s); a gap that short is not a gap, and "
                  f"balancing there would be changing something that matters",
                  file=sys.stderr)
            return 1
        result = (sum(data) + len(data) - 1) & 0xFF
        data[place] = (data[place] + want - result) & 0xFF
        again = (sum(data) + len(data) - 1) & 0xFF
        if again != want:
            print(f"error: balancing did not converge: ${again:02X}",
                  file=sys.stderr)
            return 1
        print(f"balanced at ${origin + place:04X}: ADCB self-test returns "
              f"${want:02X}, using the largest gap ${low:04X}-${high:04X}")
        image = bytes(data)

    with open(args.output, "wb") as handle:
        handle.write(image)

    if args.export:
        with open(args.export, "w") as handle:
            for name in sorted(worker.symbols, key=lambda n: worker.symbols[n]):
                handle.write(f"{name} {worker.symbols[name]:04X}\n")

    if args.map:
        # One row per source line that produced bytes: which line, where it
        # landed, what it says, and how many bytes it became. Two builds of
        # the same source must agree on every row except the size of a relaxed
        # branch, and that is a comparison no heuristic is involved in. The
        # address is written out rather than left to be re-derived by summing
        # lengths, because that sum is wrong the moment an org, an equate or a
        # relaxed branch enters, and a consumer that gets it wrong fails open.
        with open(args.map, "w") as handle:
            for index, address, size, mnemonic, operand in worker.emitted:
                handle.write(f"{index}\t{address:04X}\t{mnemonic}\t"
                             f"{operand}\t{size}\n")
    print(f"{args.source}: {len(image)} bytes at ${origin:04X} -> "
          f"{args.output} ({len(worker.symbols)} symbols)"
          + (f", {len(worker.shortened)} branches shortened"
             if worker.shortened else "")
          + (f", {worker.reclaimed} bytes reclaimed"
             if getattr(worker, "reclaimed", 0) else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
