module tb_book;

  // ---- settings ----
  localparam int    MAX_MSGS = 300_000;   // how much of the day to replay (0 = all)

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

  // Record every top-of-book update, same format as python/order_book.py
  integer fout;
  integer updates = 0;
  initial fout = $fopen("sim/book_out.txt", "w");

  always @(posedge clk) begin
    if (tob_valid) begin
      $fwrite(fout, "%0d,%0d,%0d,%0d,%0d\n",
              tob_ts, bid_price, bid_shares, ask_price, ask_shares);
      updates++;
    end
  end

  initial begin
    wait (done);
    repeat (2000) @(posedge clk);         // let the last message finish
    $display("book: %0d top-of-book updates", updates);
    $display("errors: ot_full=%0d lvl_full=%0d lvl_miss=%0d",
             err_ot_full, err_lvl_full, err_lvl_miss);
    $fclose(fout);
    $finish;
  end

endmodule