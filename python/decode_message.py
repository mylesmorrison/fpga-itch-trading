import struct

body = bytes.fromhex("58 01 80 b4 4e 00 00 00 2a 00 00 00 01")
#print(struct.unpack(">cIII", body))

FORMATS = {
    "A": ">cIIcI6sIc",
    "S": ">cIc",
    "E": ">cIIII",
    "X": ">cIII",
    "P": ">cIIcI6sII",
}

def decode_message(body):
    mtype = body[0:1].decode("ascii")
    return struct.unpack(FORMATS[mtype], body)

