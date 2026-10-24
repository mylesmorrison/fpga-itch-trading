def parse_line(line):
    t = line[8]
    e = t.encode("ascii")
    ts = int(line[0:8])
    if t == "S":
        return (e, ts, line[9].encode("ascii"))
    if t == "A":
        return (e, ts, int(line[9:18]), line[18].encode("ascii"), int(line[19:25]),
                line[25:31].encode("ascii"), int(line[31:41]), line[41].encode("ascii"))
    if t == "E":
        return (e, ts, int(line[9:18]), int(line[18:24]), int(line[24:33]))
    if t == "X":
        return (e, ts, int(line[9:18]), int(line[18:24]))
    if t == "P":
        return (e, ts, int(line[9:18]), line[18].encode("ascii"), int(line[19:25]),
                line[25:31].encode("ascii"), int(line[31:41]), int(line[41:50]))