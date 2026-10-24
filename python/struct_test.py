import struct
from uu import encode

line = "25203847A       42B     1DELL       10000Y"

# this is splitting it into variables for A order book type
ts     = int(line[0:8]) #integer
mtype  = line[8] #ascii code
ref    = int(line[9:18]) #also fully integer
side   = line[18] # ascii code
shares = int(line[19:25]) # integer
stock  = line[25:31] # ascii code
price  = int(line[31:41]) #integer
disp   = line[41] #ascii
# A format
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

#print(body.hex(" "))
# S format
line = "25200001SS"
ts = int(line[0:8])
mtype = line[8]
event_code = line[9]
body = struct.pack(">cIc",
                   mtype.encode("ascii"),
                   ts,
                   event_code.encode("ascii")
                  )
#print(body.hex(" "))
# E format
line = "25226306E       65   100        1"
ts = int(line[0:8])
mtype = line[8]
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
#print(body.hex(" "))
# X format
line = "25211982X       42     1"
ts = int(line[0:8])
mtype = line[8]
ref = int(line[9:18])
shares = int(line[18:24])
body = struct.pack(">cIII",
                   mtype.encode("ascii"),
                   ts,
                   ref,
                   shares
                   )
#print(body.hex(" "))
# P format
line = "25396808P      125S   100SPY       911900        3"
mtype  = line[8]
ts     = int(line[0:8])
ref    = int(line[9:18])
side   = line[18]
shares = int(line[19:25])
stock  = line[25:31]
price  = int(line[31:41])
match  = int(line[41:50])
body = struct.pack(">cIIcI6sII",
                   mtype.encode("ascii"),  # c
                   ts,                     # I
                   ref,                    # I
                   side.encode("ascii"),   # c
                   shares,                 # I
                   stock.encode("ascii"),  # 6s
                   price,                  # I
                   match)                  # I

#print(body.hex(" "))
#print(len(body))
print(bytes(len(body)) + body)