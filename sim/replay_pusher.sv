// Simulation-only: reads a length-prefixed binary ITCH file and pushes it
// out one byte per clock on a valid/ready interface.
module replay_pusher #(
  parameter string FILE          = "data/sample.bin",
  parameter int    CYCLES_PER_MS = 10,   // 1 ms of market time = this many clock cycles
  parameter int    MAX_MSGS      = 0     // stop after this many messages (0 = whole file)
) (
  input  logic       clk,
  input  logic       rst_n,
  output logic [7:0] data,
  output logic       valid,
  input  logic       ready,
  output logic       done
);

  integer     fd;
  integer     c;
  integer     len;
  integer     i;
  integer     msg_count;
  logic [7:0] msg [0:255];

  logic [31:0] ts;            // this message's timestamp (ms since midnight)
  logic [31:0] first_ts;      // timestamp of the first message
  logic [63:0] cycle;         // clock cycles since reset released
  logic [63:0] start_cycle;   // cycle when the first message was sent
  logic [63:0] target;        // cycle this message is scheduled for
  integer      late_count;    // messages that could not go out on schedule

  // free-running cycle counter
  always @(posedge clk) begin
    if (!rst_n) cycle <= 0;
    else        cycle <= cycle + 1;
  end

  // Put one byte on the bus and hold it until the receiver takes it.
  task automatic send_byte(input logic [7:0] b);
    data  <= b;
    valid <= 1'b1;
    do @(posedge clk); while (!ready);   // transfer happens on an edge where ready is high
  endtask

  initial begin
    data      = 8'h00;
    valid     = 1'b0;
    done      = 1'b0;
    msg_count = 0;
    late_count = 0;

    fd = $fopen(FILE, "rb");
    if (fd == 0) begin
      $display("ERROR: could not open %s", FILE);
      $finish;
    end

    // wait until reset is released
    wait (rst_n);
    @(posedge clk);

    len = $fgetc(fd);
    while (len != -1 && (MAX_MSGS == 0 || msg_count < MAX_MSGS)) begin
      for (i = 0; i < len; i++) begin
        c = $fgetc(fd);
        msg[i] = c[7:0];
      end

      // ---- pacing ----
      ts = {msg[1], msg[2], msg[3], msg[4]};
      if (msg_count == 0) begin
        first_ts    = ts;
        start_cycle = cycle;
      end
      target = start_cycle + (ts - first_ts) * CYCLES_PER_MS;

      if (cycle > target)
        late_count++;                    // still busy sending earlier messages: send now
      while (cycle < target)
        @(posedge clk);                  // idle (valid low) until scheduled time

      send_byte(len[7:0]);               // length byte first
      for (i = 0; i < len; i++)
        send_byte(msg[i]);               // then the body

      valid <= 1'b0;                     // drop valid after each message (only visible if there is a gap before the next)
      msg_count++;
      len = $fgetc(fd);
    end

    $fclose(fd);
    $display("pusher: sent %0d messages, %0d sent late (burst)", msg_count, late_count);
    $display("pusher: market time %0d ms replayed in %0d cycles", ts - first_ts, cycle - start_cycle);
    done <= 1'b1;
  end

endmodule