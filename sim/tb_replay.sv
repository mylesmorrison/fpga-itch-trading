module tb_replay;

  logic       clk = 0;
  logic       rst_n = 0;
  logic [7:0] data;
  logic       valid;
  logic       ready;
  logic       done;

  integer     bytes_received = 0;

  localparam int DUMP_NS = 2_000_000;   // record the first 2 ms of sim time (100k cycles)

  // 50 MHz clock: 20 ns period
  always #10 clk = ~clk;

  // reset for a few cycles
  initial begin
    repeat (5) @(posedge clk);
    rst_n <= 1'b1;
  end

  replay_pusher #(.FILE("data/sample.bin")) pusher (
    .clk(clk), .rst_n(rst_n),
    .data(data), .valid(valid), .ready(ready),
    .done(done)
  );

  // Dummy receiver: ready is randomly high 3/4 of the time,
  // to test that the pusher waits correctly when ready is low.
  always @(posedge clk) begin
    if (!rst_n) ready <= 1'b0;
    else        ready <= ($urandom % 4) != 0;
  end

  // Count every byte that actually transfers
  always @(posedge clk) begin
    if (valid && ready) begin
      if (bytes_received < 8)
        $display("t=%0t  byte %0d = %h", $time, bytes_received, data);
      bytes_received++;
    end
  end

  // Waveform recording: top-level signals only, first 2 ms only
  initial begin
    $dumpfile("sim/tb_replay.vcd");
    $dumpvars(1, tb_replay);
    #(DUMP_NS) $dumpoff;
  end

  // End of simulation
  initial begin
    wait (done);
    repeat (5) @(posedge clk);
    $display("receiver: got %0d bytes", bytes_received);
    $finish;
  end

endmodule