module tb_parser;

  logic clk = 0;
  logic rst_n = 0;

  // pusher -> parser
  logic [7:0] data;
  logic       valid;
  logic       ready;
  logic       done;

  // parser outputs
  logic        msg_valid;
  logic [7:0]  msg_type;
  logic [31:0] timestamp, order_ref, shares, price, match_num;
  logic [7:0]  side, display, event_code;
  logic [47:0] stock;

  integer fout;
  integer msgs_out = 0;

  always #10 clk = ~clk;

  initial begin
    repeat (5) @(posedge clk);
    rst_n <= 1'b1;
  end

  // CYCLES_PER_MS = 1 squeezes the timing, so lots of messages arrive
  // back to back: a good stress test for the parser.
  replay_pusher #(.FILE("data/sample.bin"), .CYCLES_PER_MS(1)) pusher (
    .clk(clk), .rst_n(rst_n),
    .data(data), .valid(valid), .ready(ready),
    .done(done)
  );

  itch_parser dut (
    .clk(clk), .rst_n(rst_n),
    .in_data(data), .in_valid(valid), .in_ready(ready),
    .msg_valid(msg_valid),
    .msg_type(msg_type), .timestamp(timestamp), .order_ref(order_ref),
    .side(side), .shares(shares), .stock(stock), .price(price),
    .match_num(match_num), .display(display), .event_code(event_code)
  );

  // Write every decoded message to a file, one per line, comma-separated
  initial fout = $fopen("sim/parser_out.txt", "w");

  always @(posedge clk) begin
    if (msg_valid) begin
      case (msg_type)
        "S": $fwrite(fout, "S,%0d,%c\n", timestamp, event_code);
        "A": $fwrite(fout, "A,%0d,%0d,%c,%0d,%s,%0d,%c\n",
                     timestamp, order_ref, side, shares, stock, price, display);
        "E": $fwrite(fout, "E,%0d,%0d,%0d,%0d\n",
                     timestamp, order_ref, shares, match_num);
        "X": $fwrite(fout, "X,%0d,%0d,%0d\n",
                     timestamp, order_ref, shares);
        "P": $fwrite(fout, "P,%0d,%0d,%c,%0d,%s,%0d,%0d\n",
                     timestamp, order_ref, side, shares, stock, price, match_num);
        default: $fwrite(fout, "?,%0d\n", timestamp);
      endcase
      msgs_out++;
    end
  end

  initial begin
    $dumpfile("sim/tb_parser.vcd");
    $dumpvars(1, tb_parser);
    #(2_000_000) $dumpoff;
  end

  initial begin
    wait (done);
    repeat (10) @(posedge clk);
    $display("parser: decoded %0d messages", msgs_out);
    $fclose(fout);
    $finish;
  end

endmodule