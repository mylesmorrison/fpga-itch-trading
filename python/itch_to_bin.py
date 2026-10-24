from convert_line import convert_line

with open("S010303-v2.txt", "r") as fin, open("S010303-v2.bin", "wb") as fout:
    for line in fin:
        line = line.rstrip("\r\n")
        if not line:
            continue
        msg = convert_line(line)
        fout.write(msg)

# for checking
with open("S010303-v2.bin", "rb") as f:
    print(f.read(40).hex(" "))