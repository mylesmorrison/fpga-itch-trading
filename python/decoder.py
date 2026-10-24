from decode_message import decode_message
from parser import parse_line

with open("S010303-v2.bin", "rb") as f:
    data = f.read()

pos = 0
count = 0
bad = 0

with open("S010303-v2.txt", "r") as ftxt:
    for line in ftxt:
        line = line.rstrip("\r\n")
        if not line:
            continue

        length = data[pos]
        body = data[pos + 1 : pos + 1 + length]
        pos += 1 + length

        count += 1
        if decode_message(body) != parse_line(line):
            bad += 1
            if bad <= 5:
                print("MISMATCH:", repr(line), decode_message(body))

print("messages:", count, "mismatches:", bad)
print("leftover bytes:", len(data) - pos)
