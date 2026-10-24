# fpga-itch-trading

Parsing Nasdaq ITCH market data on an FPGA.

The Python code in `python/` is the reference model: it converts the fixed-width
ITCH 2.0 text feed into a compact binary stream (the input the hardware will
parse) and checks that the binary decodes back to the same messages. The RTL
and testbench come next.

## Layout

```
python/   reference encoder/decoder and scratch scripts
rtl/      HDL for the parser (to do)
sim/      testbenches (to do)
docs/     notes
data/     market data files (not tracked in git)
```

## Data

The sample day is `S010303-v2.txt`, an ITCH 2.0 text file with one message per
line. Put it in `data/`. It holds five message types:

| Type | Message       | Fields                                              |
| ---- | ------------- | --------------------------------------------------- |
| `S`  | System event  | timestamp, event code                               |
| `A`  | Add order     | timestamp, order ref, side, shares, stock, price, display |
| `E`  | Order executed| timestamp, order ref, shares, match number          |
| `X`  | Order cancel  | timestamp, order ref, shares                        |
| `P`  | Trade         | timestamp, order ref, side, shares, stock, price, match number |

Timestamps are milliseconds since midnight, prices have 4 implied decimals, and
stock symbols are 6 characters, space-padded.

## Binary format

Each message is a 1-byte length followed by a big-endian body with no padding
(Python `struct` formats in `python/decode_message.py`):

| Type | Body layout                                                     | Bytes |
| ---- | --------------------------------------------------------------- | ----- |
| `S`  | type(1) ts(4) event(1)                                          | 6     |
| `A`  | type(1) ts(4) ref(4) side(1) shares(4) stock(6) price(4) disp(1) | 25    |
| `E`  | type(1) ts(4) ref(4) shares(4) match(4)                         | 17    |
| `X`  | type(1) ts(4) ref(4) shares(4)                                  | 13    |
| `P`  | type(1) ts(4) ref(4) side(1) shares(4) stock(6) price(4) match(4) | 28    |

## Usage

The scripts open the data files by name, so run them from `data/`:

```bash
cd data
python ../python/itch_to_bin.py   # writes S010303-v2.bin
python ../python/decoder.py       # round-trip check: decodes the .bin and compares with the .txt
```

`decoder.py` prints the message count, the number of mismatches and any
leftover bytes.
