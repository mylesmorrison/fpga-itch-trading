# Compare the SystemVerilog parser's output (sim/parser_out.txt) against
# a Python decode of the same binary file (data/sample.bin).
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

FORMATS = {
    "S": ">cIc",
    "A": ">cIIcI6sIc",
    "E": ">cIIII",
    "X": ">cIII",
    "P": ">cIIcI6sII",
}

def to_line(body):
    """Decode one message body into the same text format the testbench writes."""
    t = body[0:1].decode("ascii")
    f = struct.unpack(FORMATS[t], body)
    # turn any bytes fields (type, side, stock, ...) into strings
    f = [x.decode("ascii") if isinstance(x, bytes) else x for x in f]
    return ",".join(str(x) for x in f)

# Expected: decode the .bin in Python
expected = []
data = (ROOT / "data" / "sample.bin").read_bytes()
pos = 0
while pos < len(data):
    length = data[pos]
    expected.append(to_line(data[pos + 1 : pos + 1 + length]))
    pos += 1 + length

# Actual: what the hardware parser produced
actual = (ROOT / "sim" / "parser_out.txt").read_text().splitlines()

print(f"expected {len(expected)} messages, parser produced {len(actual)}")

mismatches = 0
for i, (e, a) in enumerate(zip(expected, actual)):
    if e != a:
        mismatches += 1
        if mismatches <= 5:
            print(f"message {i}:\n  expected {e!r}\n  parser   {a!r}")

if mismatches == 0 and len(expected) == len(actual):
    print("PASS: every message matches")
else:
    print(f"FAIL: {mismatches} mismatches")