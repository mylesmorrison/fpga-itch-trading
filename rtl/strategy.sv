// EMA-crossover strategy (synthesizable)
//
// Watches the top of book. Keeps a fast and a slow exponential moving
// average (EMA) of the mid price. When the fast one is clearly above the
// slow one, hold +QTY shares; clearly below, hold -QTY. Trades are
// simulated fills at the current best price: buys at the ask, sells at
// the bid.
//
// All maths is shifts, adds and compares: no multipliers or dividers
// in the main path.

module strategy #(
  parameter int K_FAST = 4,          // fast EMA weight = 1/2^K_FAST
  parameter int K_SLOW = 8,          // slow EMA weight = 1/2^K_SLOW
  parameter logic signed [47:0] THRESH = 48'sd51200,  // 1 cent in x units
  parameter int WARMUP = 64,         // quotes before trading starts
  parameter int QTY    = 100         // position size
) (
  input  logic        clk,
  input  logic        rst_n,

  // top of book in (from the order book)
  input  logic        tob_valid,
  input  logic [31:0] tob_ts,
  input  logic [31:0] bid_price,
  input  logic [31:0] ask_price,

  // trades out
  output logic        trade_valid,   // pulses for one cycle per trade
  output logic [31:0] trade_ts,
  output logic [7:0]  trade_side,    // ASCII B or S
  output logic [31:0] trade_qty,
  output logic [31:0] trade_price,

  // running state
  output logic signed [31:0] position,  // shares held (+long / -short)
  output logic signed [63:0] cash,      // price units * shares
  output logic signed [63:0] pnl        // cash + position marked at last mid
);

  localparam logic signed [31:0] QTY_S = 32'(QTY);
  localparam logic [7:0]         WARM  = 8'(WARMUP);

  // ---------------- stage 1: update the averages ----------------
  logic signed [47:0] x;                // mid * 2, with 8 fractional bits
  logic signed [47:0] ema_fast, ema_slow;
  logic [7:0]         count;            // valid quotes seen, stops at WARMUP
  logic [31:0]        last_bid, last_ask;
  logic [31:0]        q_ts;             // timestamp of the quote being acted on
  logic               upd;              // averages were just updated

  // (bid + ask) is 33 bits; << 8 makes 41; pad to 48 and treat as signed
  assign x = $signed({7'd0, ({1'b0, bid_price} + {1'b0, ask_price}), 8'd0});

  logic quote_ok;
  assign quote_ok = tob_valid && bid_price != 32'd0 && ask_price != 32'd0;

  // ---------------- stage 2: decide and trade ----------------
  logic signed [31:0] target;
  logic signed [31:0] q;                // shares to trade (+buy / -sell)
  logic signed [31:0] q_abs;

  always_comb begin
    if (ema_fast > ema_slow + THRESH)      target = QTY_S;
    else if (ema_fast < ema_slow - THRESH) target = -QTY_S;
    else                                   target = position;
  end

  assign q     = target - position;
  assign q_abs = (q < 0) ? -q : q;

  // mark-to-market: cash + position * last mid
  // mid = (bid + ask) / 2: dropping bit 0 is the divide by 2, so it's unused on purpose
  /* verilator lint_off UNUSEDSIGNAL */
  logic [32:0] mid_sum;
  /* verilator lint_on UNUSEDSIGNAL */
  assign mid_sum = {1'b0, last_bid} + {1'b0, last_ask};
  assign pnl = cash + 64'(position) * $signed({32'd0, mid_sum[32:1]});

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      ema_fast    <= '0;
      ema_slow    <= '0;
      count       <= '0;
      last_bid    <= '0;
      last_ask    <= '0;
      upd         <= 1'b0;
      position    <= '0;
      cash        <= '0;
      trade_valid <= 1'b0;
    end else begin
      upd         <= 1'b0;
      trade_valid <= 1'b0;

      // stage 1
      if (quote_ok) begin
        last_bid <= bid_price;
        last_ask <= ask_price;
        q_ts     <= tob_ts;
        if (count == 8'd0) begin
          ema_fast <= x;
          ema_slow <= x;
        end else begin
          ema_fast <= ema_fast + ((x - ema_fast) >>> K_FAST);
          ema_slow <= ema_slow + ((x - ema_slow) >>> K_SLOW);
        end
        if (count < WARM)
          count <= count + 8'd1;
        upd <= 1'b1;
      end

      // stage 2 (one cycle later, using the updated averages)
      if (upd && count >= WARM && target != position) begin
        trade_valid <= 1'b1;
        trade_ts    <= q_ts;
        trade_qty   <= q_abs;
        if (q > 0) begin                       // buy at the ask
          trade_side  <= "B";
          trade_price <= last_ask;
          cash        <= cash - 64'(q_abs) * $signed({32'd0, last_ask});
        end else begin                         // sell at the bid
          trade_side  <= "S";
          trade_price <= last_bid;
          cash        <= cash + 64'(q_abs) * $signed({32'd0, last_bid});
        end
        position <= target;
      end
    end
  end

endmodule