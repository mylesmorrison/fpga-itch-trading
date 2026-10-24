import struct

def convert_line(line):
    mtype = line[8] #always the case
    ts = int(line[0:8]) #also always the case for timestamp

    # conditional for each type of line
    # either A, S, E, X, P

    if mtype == "A":
        ref = int(line[9:18])  # also fully integer
        side = line[18]  # ascii code
        shares = int(line[19:25])  # integer
        stock = line[25:31]  # ascii code
        price = int(line[31:41])  # integer
        disp = line[41]  # ascii
        body = struct.pack(">cIIcI6sIc",
                           mtype.encode("ascii"),
                           ts,
                           ref,
                           side.encode("ascii"),
                           shares,
                           stock.encode("ascii"),
                           price,
                           disp.encode("ascii")
                           )

    elif mtype == "S":
        event_code = line[9]
        body = struct.pack(">cIc",
                           mtype.encode("ascii"),
                           ts,
                           event_code.encode("ascii")
                           )
    elif mtype == "E":
        ref = int(line[9:18])
        shares = int(line[18:24])
        match = int(line[24:33])
        body = struct.pack(">cIIII",
                           mtype.encode("ascii"),
                           ts,
                           ref,
                           shares,
                           match
                           )
    elif mtype == "X":
        ref = int(line[9:18])
        shares = int(line[18:24])
        body = struct.pack(">cIII",
                           mtype.encode("ascii"),
                           ts,
                           ref,
                           shares
                           )
    elif mtype == "P":
        ref = int(line[9:18])
        side = line[18]
        shares = int(line[19:25])
        stock = line[25:31]
        price = int(line[31:41])
        match = int(line[41:50])
        body = struct.pack(">cIIcI6sII",
                           mtype.encode("ascii"),  # c
                           ts,  # I
                           ref,  # I
                           side.encode("ascii"),  # c
                           shares,  # I
                           stock.encode("ascii"),  # 6s
                           price,  # I
                           match)  # I

    else:
        raise ValueError(f"Uknown message type: {mtype!r}")

    return bytes([len(body)]) + body

#print(convert_line("25211982X       42     1").hex(" "))
