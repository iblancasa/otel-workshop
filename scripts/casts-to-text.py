#!/usr/bin/env python3
"""Convert asciinema v2 .cast files into plain terminal transcripts.

Input:  site/src/terminals/**/*.cast   (recorded by <flavour>/scripts/record-casts.sh)
Output: site/src/terminals/**/*.txt    (what the <Terminal> component renders)

Keeps the ANSI colour sequences the recorder used for the prompt; the
component turns them into spans. Everything else (cursor movement, carriage
returns from progress bars) is flattened so the transcript reads like a
scrollback buffer.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "site" / "src" / "terminals"

# Keep SGR (colour/bold) sequences, drop every other escape sequence.
OTHER_ESC = re.compile(r"\x1b\[[0-9;?]*[A-Za-ln-z]|\x1b\][^\x07]*\x07|\x1b[()][AB012]|\x1b[=>]")


def flatten(text: str) -> str:
    lines = []
    for raw in text.split("\n"):
        # "\r" overwrites the line: keep what was last written.
        if "\r" in raw:
            raw = raw.split("\r")[-1] if raw.split("\r")[-1].strip() else raw.split("\r")[-2]
        raw = OTHER_ESC.sub("", raw)
        lines.append(raw.rstrip())
    # trim trailing blank lines
    while lines and not lines[-1].strip():
        lines.pop()
    return "\n".join(lines) + "\n"


def convert(cast: Path) -> Path:
    out = []
    with cast.open() as f:
        next(f)  # header
        for line in f:
            try:
                _, kind, data = json.loads(line)
            except ValueError:
                continue
            if kind == "o":
                out.append(data)
    txt = cast.with_suffix(".txt")
    txt.write_text(flatten("".join(out)))
    return txt


def main(argv):
    casts = [Path(a) for a in argv] or sorted(SRC.rglob("*.cast"))
    for c in casts:
        t = convert(c)
        print(f"{c.relative_to(SRC) if c.is_relative_to(SRC) else c} -> {t.name} ({t.stat().st_size} bytes)")


if __name__ == "__main__":
    main(sys.argv[1:])
