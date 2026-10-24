# Compare the hardware strategy's trades (sim/trades_out.txt) against the
# Python model (data/trades_msft.txt). Like check_book.py, a partial-day
# simulation should match the START of the Python file.
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

expected = (ROOT / "data" / "trades_msft.txt").read_text().splitlines()
actual = (ROOT / "sim" / "trades_out.txt").read_text().splitlines()

print(f"hardware made {len(actual)} trades "
      f"(Python has {len(expected)} for the full day)")

if len(actual) > len(expected):
    print("FAIL: more trades than the Python model")
else:
    mismatches = 0
    for i, (e, a) in enumerate(zip(expected, actual)):
        if e != a:
            mismatches += 1
            if mismatches <= 5:
                print(f"trade {i}:\n  expected {e}\n  hardware {a}")
    if mismatches == 0:
        print(f"PASS: all {len(actual)} trades match")
    else:
        print(f"FAIL: {mismatches} mismatches")