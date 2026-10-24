# fpga-itch-trading

Parsing Nasdaq ITCH market data and trading on it in an FPGA.

The hardware pipeline, all in SystemVerilog:

```
binary ITCH bytes -> itch_parser -> order_book -> strategy -> trades
```

- `itch_parser` decodes the length-prefixed byte stream into messages.
- `order_book` tracks every live order for one stock (MSFT) and outputs the
  best bid and ask after each change.
- `strategy` trades a fast/slow EMA crossover of the mid price, with
  simulated fills at the best bid or ask.

Each stage has a Python reference model, and the testbench output is checked
line by line against it.

## Layout

```
rtl/      synthesizable parser, order book and strategy
sim/      testbenches and the replay pusher that feeds them the binary file
python/   binary encoder, reference models and output checkers
data/     market data (only the 1,000-message sample is tracked in git)
docs/     notes
```

## Data

The sample day is `S010303-v2.txt`, an ITCH 2.0 text file with one message per
line (6,115,981 messages). It's too large for GitHub, so put it in `data/`
yourself. `data/sample.txt` and `data/sample.bin` are its first 1,000 messages.

The file holds five message types:

| Type | Message        | Fields                                                         | Count     |
| ---- | -------------- | -------------------------------------------------------------- | --------- |
| `S`  | System event   | timestamp, event code                                          | 2         |
| `A`  | Add order      | timestamp, order ref, side, shares, stock, price, display      | 2,921,796 |
| `E`  | Order executed | timestamp, order ref, shares, match number                     | 257,338   |
| `X`  | Order cancel   | timestamp, order ref, shares                                   | 2,762,898 |
| `P`  | Trade          | timestamp, order ref, side, shares, stock, price, match number | 173,947   |

Timestamps are milliseconds since midnight, prices have 4 implied decimals, and
stock symbols are 6 characters, space-padded.

## Binary format

Each message is a 1-byte length followed by a big-endian body with no padding
(Python `struct` formats in `python/decode_message.py`):

| Type | Body layout                                                       | Bytes |
| ---- | ----------------------------------------------------------------- | ----- |
| `S`  | type(1) ts(4) event(1)                                            | 6     |
| `A`  | type(1) ts(4) ref(4) side(1) shares(4) stock(6) price(4) disp(1)  | 25    |
| `E`  | type(1) ts(4) ref(4) shares(4) match(4)                           | 17    |
| `X`  | type(1) ts(4) ref(4) shares(4)                                    | 13    |
| `P`  | type(1) ts(4) ref(4) side(1) shares(4) stock(6) price(4) match(4) | 28    |

## Usage

Needs Python 3 and [Icarus Verilog](https://steveicarus.github.io/iverilog/)
(tested with 13.0).

Make the binary file and check it round-trips. These two scripts open the data
files by name, so run them from `data/`:

```bash
cd data
python ../python/itch_to_bin.py   # writes S010303-v2.bin
python ../python/decoder.py       # decodes the .bin and compares with the .txt
cd ..
```

Build the Python answer keys (from the repo root):

```bash
python python/order_book.py       # writes data/book_msft.txt
python python/strategy.py         # writes data/trades_msft.txt
```

Run the testbenches from the repo root:

```bash
# parser alone, on the 1,000-message sample
iverilog -g2012 -o sim/tb_parser.vvp sim/tb_parser.sv sim/replay_pusher.sv rtl/itch_parser.sv
vvp -n sim/tb_parser.vvp
python python/check_parser.py

# full pipeline, on the first 300,000 messages of the day (MAX_MSGS in tb_system.sv)
iverilog -g2012 -o sim/tb_system.vvp sim/tb_system.sv sim/replay_pusher.sv \
  rtl/itch_parser.sv rtl/order_book.sv rtl/strategy.sv
vvp -n sim/tb_system.vvp
python python/check_book.py
python python/check_trades.py
```

## Results

Run on the 2003-01-03 sample day with Icarus Verilog 13.0. Every hardware
output so far matches its Python model exactly.

| Check                  | Run                                       | Result                                  |
| ---------------------- | ----------------------------------------- | --------------------------------------- |
| Binary encoding        | `decoder.py`, full day                    | 6,115,981 messages, 0 mismatches        |
| Parser                 | `tb_parser`, 1,000-message sample         | 1,000 / 1,000 messages match            |
| Order book             | `tb_system`, first 300,000 messages       | 6,727 / 6,727 top-of-book updates match |
| Strategy               | `tb_system`, first 300,000 messages       | 12 / 12 trades match                    |
| Order book table sizes | `tb_system`, first 300,000 messages       | no overflow or missing-level errors     |

**Hardware run.** The first 300,000 messages cover 07:00:00 to 09:45:21 market
time. The pipeline gets through them in 9.8 million clock cycles, about 33
cycles per message. At the testbench's 50 MHz clock, 2 h 45 min of market data
takes 196 ms. The design hasn't been synthesized yet, so there are no timing or
resource numbers.

**Full-day Python models (MSFT only):**

- Order book: 160,021 top-of-book updates. The busiest moments had 584 live
  orders and 190 price levels on one side. The hardware tables hold 8,192
  orders (1,024 sets × 8 ways) and 256 levels per side.
- Strategy: 241 trades, ending long 100 shares, with a P&L of −$583.80 marked
  at the last mid price. It's a test load for the pipeline, not a profitable
  strategy. Fills are assumed at the best bid or ask, with no fees.

The full day hasn't been simulated in hardware yet.
