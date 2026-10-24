# Reference model for a simple EMA-crossover strategy.
#
# Reads the top-of-book stream from data/book_msft.txt (made by order_book.py),
# trades when a fast moving average of the mid price crosses a slow one, and
# writes every trade to data/trades_msft.txt.
#
# All maths is integer and uses shifts, exactly like the hardware version.
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IN_FILE = ROOT / "data" / "book_msft.txt"
OUT_FILE = ROOT / "data" / "trades_msft.txt"

K_FAST = 4          # fast EMA: each new mid moves it 1/16 of the way
K_SLOW = 8          # slow EMA: each new mid moves it 1/256 of the way
THRESH = 51200      # 1 cent, in the units of x below (100 * 2 * 256)
WARMUP = 64         # quotes to see before trading
QTY = 100           # position is always -QTY, 0 or +QTY shares


def dollars(units):
    return units / 10000


ema_fast = ema_slow = 0
count = 0           # valid quotes seen (stops at WARMUP)
position = 0        # shares held: +long, -short
cash = 0            # price units (1/10000 dollar) * shares
last_bid = last_ask = 0
trades = 0

with open(IN_FILE) as fin, open(OUT_FILE, "w") as fout:
    for line in fin:
        ts, bid, bid_sz, ask, ask_sz = map(int, line.split(","))

        # need both sides of the book to have a mid price
        if bid == 0 or ask == 0:
            continue
        last_bid, last_ask = bid, ask

        # x = mid price * 2, with 8 extra fractional bits
        x = (bid + ask) << 8

        if count == 0:
            ema_fast = ema_slow = x                  # start both at the first price
        else:
            ema_fast += (x - ema_fast) >> K_FAST
            ema_slow += (x - ema_slow) >> K_SLOW
        if count < WARMUP:
            count += 1

        if count < WARMUP:
            continue

        # where do we want to be?
        target = position
        if ema_fast > ema_slow + THRESH:
            target = QTY                             # trending up: go long
        elif ema_fast < ema_slow - THRESH:
            target = -QTY                            # trending down: go short

        if target != position:
            q = target - position
            if q > 0:                                # buy at the ask
                side, qty, price = "B", q, ask
                cash -= qty * price
            else:                                    # sell at the bid
                side, qty, price = "S", -q, bid
                cash += qty * price
            position = target
            trades += 1
            fout.write(f"{ts},{side},{qty},{price},{position},{cash}\n")

            if trades <= 5:
                print(f"ts={ts}  {side} {qty} @ {dollars(price):.4f}  "
                      f"position {position:+d}")

pnl = cash + position * ((last_bid + last_ask) // 2)
print(f"\ntrades: {trades}")
print(f"final position: {position:+d}")
print(f"P&L (marked at last mid): ${dollars(pnl):,.2f}")