# Compare the SystemVerilog order book (sim/book_out.txt) against the
# Python model (data/book_msft.txt). The simulation usually replays only
# part of the day, so its output should match the START of the Python file.
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

expected = (ROOT / "data" / "book_msft.txt").read_text().splitlines()
actual = (ROOT / "sim" / "book_out.txt").read_text().splitlines()

print(f"hardware produced {len(actual)} updates "
      f"(Python has {len(expected)} for the full day)")

if len(actual) == 0:
    print("FAIL: no updates")
elif len(actual) > len(expected):
    print("FAIL: more updates than the Python model")
else:
    mismatches = 0
    for i, (e, a) in enumerate(zip(expected, actual)):
        if e != a:
            mismatches += 1
            if mismatches <= 5:
                print(f"update {i}:\n  expected {e}\n  hardware {a}")
    if mismatches == 0:
        print(f"PASS: all {len(actual)} updates match")
    else:
        print(f"FAIL: {mismatches} mismatches")