# Reference order book model for one stock.
#
# Reads the binary ITCH file, keeps a live order book for SYMBOL, and writes
# the top of book (best bid/ask and their sizes) after every message that
# changes the book. That file is the answer key for the hardware version.
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

SYMBOL = b"MSFT  "                      # 6 bytes, space-padded, like in the messages
IN_FILE = ROOT / "data" / "S010303-v2.bin"
OUT_FILE = ROOT / "data" / "book_msft.txt"

FORMATS = {
    "S": ">cIc",
    "A": ">cIIcI6sIc",
    "E": ">cIIII",
    "X": ">cIII",
    "P": ">cIIcI6sII",
}


class OrderBook:
    def __init__(self):
        # Order table: ref -> [side, price, shares remaining]
        self.orders = {}
        # Price levels: total shares waiting at each price, per side
        self.levels = {b"B": {}, b"S": {}}

    def add(self, ref, side, price, shares):
        self.orders[ref] = [side, price, shares]
        lvl = self.levels[side]
        lvl[price] = lvl.get(price, 0) + shares

    def reduce(self, ref, shares):
        """Handle an E or X. Returns False if the ref isn't one of ours."""
        order = self.orders.get(ref)
        if order is None:
            return False                # some other stock's order: ignore it

        side, price, remaining = order
        shares = min(shares, remaining) # never go below zero

        # update the order
        order[2] = remaining - shares
        if order[2] == 0:
            del self.orders[ref]

        # update its price level
        lvl = self.levels[side]
        lvl[price] -= shares
        if lvl[price] == 0:
            del lvl[price]
        return True

    def best_bid(self):
        bids = self.levels[b"B"]
        if not bids:
            return 0, 0
        p = max(bids)                   # highest buy price
        return p, bids[p]

    def best_ask(self):
        asks = self.levels[b"S"]
        if not asks:
            return 0, 0
        p = min(asks)                   # lowest sell price
        return p, asks[p]


def messages(path):
    """Yield (type, fields) for every message in a length-prefixed binary file."""
    data = path.read_bytes()
    pos = 0
    while pos < len(data):
        length = data[pos]
        body = data[pos + 1 : pos + 1 + length]
        pos += 1 + length
        mtype = body[0:1].decode("ascii")
        yield mtype, struct.unpack(FORMATS[mtype], body)


def price_str(p):
    return f"{p / 10000:.4f}" if p else "-"


book = OrderBook()
updates = 0
peak_orders = 0
peak_levels = 0

with open(OUT_FILE, "w") as fout:
    for mtype, f in messages(IN_FILE):
        changed = False

        if mtype == "A":
            _, ts, ref, side, shares, stock, price, _ = f
            if stock == SYMBOL:
                book.add(ref, side, price, shares)
                changed = True

        elif mtype in ("E", "X"):
            ts, ref, shares = f[1], f[2], f[3]
            changed = book.reduce(ref, shares)

        # P and S never change the book

        if changed:
            bid_p, bid_s = book.best_bid()
            ask_p, ask_s = book.best_ask()
            fout.write(f"{ts},{bid_p},{bid_s},{ask_p},{ask_s}\n")
            updates += 1
            peak_orders = max(peak_orders, len(book.orders))
            peak_levels = max(peak_levels, len(book.levels[b"B"]), len(book.levels[b"S"]))

            if updates <= 10:
                print(f"{mtype} ts={ts}  bid {bid_s:>6} @ {price_str(bid_p):>9}   "
                      f"ask {ask_s:>6} @ {price_str(ask_p):>9}")

print(f"\nbook updates written: {updates}")
print(f"peak live orders: {peak_orders}")
print(f"peak price levels on one side: {peak_levels}")
print(f"orders left at end of day: {len(book.orders)}")