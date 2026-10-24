"""
text = "000500"
n = int(text)
print(n)

b = n.to_bytes(2, "big")
print(b)
print(b.hex())

sym = "MSFT".ljust(8).encode("ascii")   # b'MSFT    ' -> always 8 bytes
print(sym)
"""

line = "25203847A       42B     1DELL       10000Y"
line2 = "25219975A       57S  2000LOW       389700Y"

ts = int(line[0:8]) #time stamp conver to int
mtype = line[8] #type keep ASCII
ref = int(line[9:18]) #order ref
side = line[18] #buy/sell side
shares = int(line[19:25]) #amount of shares
stock = line[25:31] #name of the stockk ASCII
price = int(line[31:41]) #price of the stock
display = line[41]

print(ts, mtype, ref, side, shares, repr(stock), price, display)

ts = int(line2[0:8]) #time stamp conver to int
mtype = line2[8] #type keep ASCII
ref = int(line2[9:18]) #order ref
side = line2[18] #buy/sell side
shares = int(line2[19:25]) #amount of shares
stock = line2[25:31] #name of the stockk ASCII
price = int(line2[31:41]) #price of the stock
display = line2[41]

print(ts, mtype, ref, side, shares, repr(stock), price, display)

line3 = "25226306E       65   100        1"

mtype = line3[8]
if mtype == "A":
    # execute for add order
    ts = int(line[0:8])  # time stamp conver to int
    mtype = line[8]  # type keep ASCII
    ref = int(line[9:18])  # order ref
    side = line[18]  # buy/sell side
    shares = int(line[19:25])  # amount of shares
    stock = line[25:31]  # name of the stockk ASCII
    price = int(line[31:41])  # price of the stock
    display = line[41]

elif mtype == "E":
    ts = int(line3[0:8])  # timestamp
    mtype = line3[8]  # the type again
    ref = int(line3[9:18])  # order ref
    shares = int(line3[18:24])  # the shares
    match = int(line3[24:33])  # unique id for this trade match no.
elif mtype == "X":
    # execute for Cancel
    ts = int(line3[0:8])  # timestamp
    mtype = line3[8] # mtype
    ref = int(line3[9:18]) # order ref number
    shares = int(line3[18:24]) # how many cancelled
elif mtype == "S":
    ts = int(line3[0:8])
    mtype = line3[8]
    event_code = line3[9] # likely start of message
elif mtype == "P":
    ts     = int(line3[0:8])
    mtype  = line3[8]
    ref    = int(line3[9:18])
    side   = line3[18]           # B or S
    shares = int(line3[19:25])
    stock  = line3[25:31]        # keep the padding
    price  = int(line3[31:41])   # 4 implied decimals
    match  = int(line3[41:50])

types = set()
with open("S010303-v2.txt") as f:
    for line in f:
        line = line.rstrip("\r\n")
        if len(line) > 8:
            types.add(line[8])
print(types)

count = 0
with open("S010303-v2.txt") as f:
    for line in f:
        line = line.rstrip("\r\n")
        if len(line) > 8 and line[8] == "P":
            print(repr(line), len(line))
            count += 1
            if count == 5:
                break

expected = {"S": 10, "A": 42, "E": 33, "X": 24, "P": 50}
bad = 0
with open("S010303-v2.txt") as f:
    for lineno, line in enumerate(f, 1):
        line = line.rstrip("\r\n")
        if len(line) <= 8:
            continue
        t = line[8]
        if len(line) != expected[t]:
            print(lineno, repr(line), len(line))
            bad += 1
print("bad lines:", bad)