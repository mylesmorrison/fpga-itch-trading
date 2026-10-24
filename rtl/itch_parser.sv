// ITCH binary parser (synthesizable)
//
// Input:  length-prefixed byte stream on a valid/ready interface.
// Output: one decoded message at a time on a valid/ready interface.
//         msg_valid stays high (and the fields stay put) until the next
//         stage takes the message with out_ready.
//
// Fields that a message type doesn't have are output as 0.

module itch_parser (
  input  logic        clk,
  input  logic        rst_n,

  // byte stream in
  input  logic [7:0]  in_data,
  input  logic        in_valid,
  output logic        in_ready,

  // decoded message out
  output logic        msg_valid,
  input  logic        out_ready,    // next stage can take the message
  output logic [7:0]  msg_type,     // ASCII: S, A, E, X, P
  output logic [31:0] timestamp,    // ms since midnight
  output logic [31:0] order_ref,
  output logic [7:0]  side,         // ASCII: B or S
  output logic [31:0] shares,
  output logic [47:0] stock,        // 6 ASCII characters
  output logic [31:0] price,        // 4 implied decimal places
  output logic [31:0] match_num,
  output logic [7:0]  display,      // ASCII: Y
  output logic [7:0]  event_code    // ASCII
);

  // Longest body we expect (P = 28 bytes). Longer messages are still
  // counted through correctly, but bytes past this aren't stored.
  localparam logic [7:0] MAX_BODY = 8'd28;

  // ---------------- receive state machine ----------------
  typedef enum logic {S_LEN, S_BODY} state_t;
  state_t state;

  logic [7:0] len;                  // body length of the current message
  logic [7:0] idx;                  // which body byte we're on
  logic [7:0] body [0:27];          // the body bytes
  logic       body_done;            // high for one cycle after the last body byte

  // Accept bytes unless a decoded message is waiting and the next
  // stage isn't taking it this cycle (backpressure).
  assign in_ready = !msg_valid || out_ready;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state     <= S_LEN;
      len       <= 8'd0;
      idx       <= 8'd0;
      body_done <= 1'b0;
    end else begin
      body_done <= 1'b0;            // default: no message finished this cycle

      if (in_valid && in_ready) begin
        case (state)
          S_LEN: begin
            len <= in_data;
            idx <= 8'd0;
            if (in_data != 8'd0)
              state <= S_BODY;
          end

          S_BODY: begin
            if (idx < MAX_BODY)
              body[idx[4:0]] <= in_data;
            idx <= idx + 8'd1;
            if (idx == len - 8'd1) begin   // that was the last body byte
              state     <= S_LEN;
              body_done <= 1'b1;
            end
          end

          default: state <= S_LEN;
        endcase
      end
    end
  end

  // ---------------- decode stage ----------------
  // Runs one cycle after the last body byte, once it's been stored.
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      msg_valid <= 1'b0;
    end else begin
      if (body_done)
        msg_valid <= 1'b1;          // new message ready
      else if (out_ready)
        msg_valid <= 1'b0;          // the next stage took it

      if (body_done) begin
        // common to every type
        msg_type  <= body[0];
        timestamp <= {body[1], body[2], body[3], body[4]};

        // clear everything else, then fill in what this type has
        order_ref  <= 32'd0;
        side       <= 8'd0;
        shares     <= 32'd0;
        stock      <= 48'd0;
        price      <= 32'd0;
        match_num  <= 32'd0;
        display    <= 8'd0;
        event_code <= 8'd0;

        case (body[0])
          "S": begin
            event_code <= body[5];
          end

          "A": begin
            order_ref <= {body[5], body[6], body[7], body[8]};
            side      <= body[9];
            shares    <= {body[10], body[11], body[12], body[13]};
            stock     <= {body[14], body[15], body[16], body[17], body[18], body[19]};
            price     <= {body[20], body[21], body[22], body[23]};
            display   <= body[24];
          end

          "E": begin
            order_ref <= {body[5], body[6], body[7], body[8]};
            shares    <= {body[9], body[10], body[11], body[12]};
            match_num <= {body[13], body[14], body[15], body[16]};
          end

          "X": begin
            order_ref <= {body[5], body[6], body[7], body[8]};
            shares    <= {body[9], body[10], body[11], body[12]};
          end

          "P": begin
            order_ref <= {body[5], body[6], body[7], body[8]};
            side      <= body[9];
            shares    <= {body[10], body[11], body[12], body[13]};
            stock     <= {body[14], body[15], body[16], body[17], body[18], body[19]};
            price     <= {body[20], body[21], body[22], body[23]};
            match_num <= {body[24], body[25], body[26], body[27]};
          end

          default: ;   // unknown type: only type + timestamp are output
        endcase
      end
    end
  end

endmodule