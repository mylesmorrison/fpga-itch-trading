// Full system: replay pusher -> parser -> order book -> strategy
module tb_system;

  // ---- settings ----
  localparam int    MAX_MSGS = 300_000;   // how much of the day to replay (0 = whole day)

  logic clk = 0;
  logic rst_n = 0;
  always #10 clk = ~clk;

  initial begin
    repeat (5) @(posedge clk);
    rst_n <= 1'b1;
  end

  // pusher -> parser
  logic [7:0] data;
  logic       valid, ready, done;

  // parser -> book
  logic        msg_valid, msg_ready;
  logic [7:0]  msg_type, side, display, event_code;
  logic [31:0] timestamp, order_ref, shares, price, match_num;
  logic [47:0] stock;

  // book outputs
  logic        tob_valid;
  logic [31:0] tob_ts, bid_price, bid_shares, ask_price, ask_shares;
  logic        err_ot_full, err_lvl_full, err_lvl_miss;

  // strategy outputs
  logic               trade_valid;
  logic [31:0]        trade_ts, trade_qty, trade_price;
  logic [7:0]         trade_side;
  logic signed [31:0] position;
  logic signed [63:0] cash, pnl;

  // CYCLES_PER_MS = 0: no pacing, run as fast as backpressure allows
  replay_pusher #(.FILE("data/S010303-v2.bin"), .CYCLES_PER_MS(0), .MAX_MSGS(MAX_MSGS)) pusher (
    .clk(clk), .rst_n(rst_n),
    .data(data), .valid(valid), .ready(ready), .done(done)
  );

  itch_parser parser (
    .clk(clk), .rst_n(rst_n),
    .in_data(data), .in_valid(valid), .in_ready(ready),
    .msg_valid(msg_valid), .out_ready(msg_ready),
    .msg_type(msg_type), .timestamp(timestamp), .order_ref(order_ref),
    .side(side), .shares(shares), .stock(stock), .price(price),
    .match_num(match_num), .display(display), .event_code(event_code)
  );

  order_book #(.SYMBOL("MSFT  ")) book (
    .clk(clk), .rst_n(rst_n),
    .msg_valid(msg_valid), .msg_ready(msg_ready),
    .msg_type(msg_type), .timestamp(timestamp), .order_ref(order_ref),
    .side(side), .shares(shares), .stock(stock), .price(price),
    .tob_valid(tob_valid), .tob_ts(tob_ts),
    .bid_price(bid_price), .bid_shares(bid_shares),
    .ask_price(ask_price), .ask_shares(ask_shares),
    .err_ot_full(err_ot_full), .err_lvl_full(err_lvl_full), .err_lvl_miss(err_lvl_miss)
  );

  strategy strat (
    .clk(clk), .rst_n(rst_n),
    .tob_valid(tob_valid), .tob_ts(tob_ts),
    .bid_price(bid_price), .ask_price(ask_price),
    .trade_valid(trade_valid), .trade_ts(trade_ts), .trade_side(trade_side),
    .trade_qty(trade_qty), .trade_price(trade_price),
    .position(position), .cash(cash), .pnl(pnl)
  );

  // Record book updates and trades, same formats as the Python models
  integer fbook, ftrade;
  integer updates = 0;
  integer trades  = 0;
  initial begin
    fbook  = $fopen("sim/book_out.txt", "w");
    ftrade = $fopen("sim/trades_out.txt", "w");
  end

  always @(posedge clk) begin
    if (tob_valid) begin
      $fwrite(fbook, "%0d,%0d,%0d,%0d,%0d\n",
              tob_ts, bid_price, bid_shares, ask_price, ask_shares);
      updates++;
    end
    if (trade_valid) begin
      // position and cash were updated on the same edge as trade_valid
      $fwrite(ftrade, "%0d,%c,%0d,%0d,%0d,%0d\n",
              trade_ts, trade_side, trade_qty, trade_price, position, cash);
      trades++;
    end
  end

  initial begin
    wait (done);
    repeat (2000) @(posedge clk);         // let the last message finish
    $display("book: %0d top-of-book updates", updates);
    $display("errors: ot_full=%0d lvl_full=%0d lvl_miss=%0d",
             err_ot_full, err_lvl_full, err_lvl_miss);
    $display("strategy: %0d trades, final position %0d", trades, position);
    $display("P&L (marked at last mid): $%0.2f", $itor(pnl) / 10000.0);
    $fclose(fbook);
    $fclose(ftrade);
    $finish;
  end

endmodule