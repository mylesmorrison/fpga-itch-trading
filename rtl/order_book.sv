// Single-symbol order book (synthesizable)
//
// Takes decoded messages from the parser (valid/ready), keeps every live
// order for SYMBOL, and outputs the top of book (best bid/ask price and
// size) after every message that changes the book.
//
// Two tables, like the Python model:
//   order table : ref -> side, price, shares remaining
//                 set-associative: SETS sets of WAYS slots, set = low ref bits
//   level table : per side, LEVELS slots of (price, total shares)
//
// One message is processed at a time by a state machine. Tables are
// searched one slot per clock cycle.

module order_book #(
  parameter logic [47:0] SYMBOL = "MSFT  ",
  parameter int          SETS   = 1024,
  parameter int          WAYS   = 8,
  parameter int          LEVELS = 256
) (
  input  logic        clk,
  input  logic        rst_n,

  // decoded messages in (from the parser)
  input  logic        msg_valid,
  output logic        msg_ready,
  input  logic [7:0]  msg_type,
  input  logic [31:0] timestamp,
  input  logic [31:0] order_ref,
  input  logic [7:0]  side,
  input  logic [31:0] shares,
  input  logic [47:0] stock,
  input  logic [31:0] price,

  // top of book out
  output logic        tob_valid,     // pulses for one cycle per update
  output logic [31:0] tob_ts,
  output logic [31:0] bid_price,     // 0 = no bids
  output logic [31:0] bid_shares,
  output logic [31:0] ask_price,     // 0 = no asks
  output logic [31:0] ask_shares,

  // sticky error flags (should stay 0)
  output logic        err_ot_full,   // an order's set had no free slot
  output logic        err_lvl_full,  // no free price-level slot
  output logic        err_lvl_miss   // reduced a level that didn't exist
);

  localparam int SET_W = $clog2(SETS);
  localparam int WAY_W = $clog2(WAYS);
  localparam int LVL_W = $clog2(LEVELS);

  localparam logic [SET_W-1:0] LAST_SET = SET_W'(SETS - 1);
  localparam logic [WAY_W-1:0] LAST_WAY = WAY_W'(WAYS - 1);
  localparam logic [LVL_W-1:0] LAST_LVL = LVL_W'(LEVELS - 1);

  localparam logic BID = 1'b0;
  localparam logic ASK = 1'b1;

  // ---------------- storage ----------------
  // order table
  logic [WAYS-1:0] ot_valid [SETS];  // one valid bit per way, packed per set
  logic [31:0] ot_ref    [SETS][WAYS];
  logic        ot_side   [SETS][WAYS];
  logic [31:0] ot_price  [SETS][WAYS];
  logic [31:0] ot_shares [SETS][WAYS];

  // level table: [side][slot]
  logic [LEVELS-1:0] lv_valid [2];  // one valid bit per slot, packed per side
  logic [31:0] lv_price  [2][LEVELS];
  logic [31:0] lv_shares [2][LEVELS];

  // ---------------- current message ----------------
  logic [7:0]  cur_type;
  logic [31:0] cur_ts, cur_ref, cur_shares, cur_price;
  logic        cur_side;
  logic [SET_W-1:0] set_idx;         // which order-table set this ref lives in
  logic [SET_W-1:0] clr;             // clear counter, used after reset

  // ---------------- search results ----------------
  logic [WAY_W-1:0] way;             // order-table scan position
  logic             hit;             // ref found
  logic [WAY_W-1:0] hit_way;
  logic             free_found;      // empty slot found in the set
  logic [WAY_W-1:0] free_way;

  logic             l_side;          // level side being changed
  logic [31:0]      l_price;         // level price being changed
  logic             l_add;           // 1 = add shares, 0 = remove shares
  logic [31:0]      l_delta;         // how many shares

  logic [LVL_W-1:0] li;              // level-table scan position
  logic             l_match;         // level with this price found
  logic [LVL_W-1:0] l_match_i;
  logic             l_free_found;    // empty level slot found
  logic [LVL_W-1:0] l_free_i;

  logic             best_found;      // best-price scan results
  logic [31:0]      best_p, best_s;

  // shares to remove for an E/X: never more than the order has left
  logic [31:0] hit_rem, reduce_by;
  assign hit_rem   = ot_shares[set_idx][hit_way];
  assign reduce_by = (cur_shares < hit_rem) ? cur_shares : hit_rem;

  // the level entry being scanned / matched
  logic        scan_valid;
  logic [31:0] scan_price, scan_shares, match_shares;
  assign scan_valid   = lv_valid [l_side][li];
  assign scan_price   = lv_price [l_side][li];
  assign scan_shares  = lv_shares[l_side][li];
  assign match_shares = lv_shares[l_side][l_match_i];

  // ---------------- state machine ----------------
  typedef enum logic [2:0] {
    CLEAR,       // after reset: empty the order table, one set per cycle
    IDLE,        // wait for a message
    OT_SCAN,     // search the order's set, one way per cycle
    OT_UPDATE,   // add / reduce / remove the order
    LVL_SCAN,    // search that side's levels for the price, one per cycle
    LVL_UPDATE,  // change the level's shares
    BEST_SCAN,   // find that side's best price, one level per cycle
    OUTPUT       // publish top of book
  } state_t;
  state_t state;

  assign msg_ready = (state == IDLE);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state        <= CLEAR;
      clr          <= '0;
      tob_valid    <= 1'b0;
      bid_price    <= 32'd0;
      bid_shares   <= 32'd0;
      ask_price    <= 32'd0;
      ask_shares   <= 32'd0;
      err_ot_full  <= 1'b0;
      err_lvl_full <= 1'b0;
      err_lvl_miss <= 1'b0;
      lv_valid[BID] <= '0;                     // small enough to clear at once
      lv_valid[ASK] <= '0;
    end else begin
      tob_valid <= 1'b0;                       // default: no update this cycle

      case (state)

        // ---------------------------------------------------------
        CLEAR: begin
          ot_valid[clr] <= '0;
          if (clr == LAST_SET) state <= IDLE;
          else                 clr   <= clr + 1'b1;
        end

        // ---------------------------------------------------------
        IDLE: begin
          if (msg_valid) begin
            cur_type   <= msg_type;
            cur_ts     <= timestamp;
            cur_ref    <= order_ref;
            cur_shares <= shares;
            cur_price  <= price;
            cur_side   <= (side == "S") ? ASK : BID;
            set_idx    <= order_ref[SET_W-1:0];
            way        <= '0;
            hit        <= 1'b0;
            free_found <= 1'b0;

            // only these messages can change our book
            if ((msg_type == "A" && stock == SYMBOL) ||
                 msg_type == "E" || msg_type == "X")
              state <= OT_SCAN;
          end
        end

        // ---------------------------------------------------------
        OT_SCAN: begin
          if (ot_valid[set_idx][way] && ot_ref[set_idx][way] == cur_ref) begin
            hit     <= 1'b1;
            hit_way <= way;
          end
          if (!ot_valid[set_idx][way] && !free_found) begin
            free_found <= 1'b1;
            free_way   <= way;
          end

          if (way == LAST_WAY) state <= OT_UPDATE;
          else                 way   <= way + 1'b1;
        end

        // ---------------------------------------------------------
        OT_UPDATE: begin
          if (cur_type == "A") begin
            if (free_found) begin
              ot_valid [set_idx][free_way] <= 1'b1;
              ot_ref   [set_idx][free_way] <= cur_ref;
              ot_side  [set_idx][free_way] <= cur_side;
              ot_price [set_idx][free_way] <= cur_price;
              ot_shares[set_idx][free_way] <= cur_shares;
              l_side  <= cur_side;
              l_price <= cur_price;
              l_add   <= 1'b1;
              l_delta <= cur_shares;
              state   <= LVL_SCAN;
            end else begin
              err_ot_full <= 1'b1;             // table too small: drop it
              state       <= IDLE;
            end
          end else if (hit) begin              // E or X for one of our orders
            ot_shares[set_idx][hit_way] <= hit_rem - reduce_by;
            if (hit_rem == reduce_by)
              ot_valid[set_idx][hit_way] <= 1'b0;   // fully gone
            l_side  <= ot_side [set_idx][hit_way];
            l_price <= ot_price[set_idx][hit_way];
            l_add   <= 1'b0;
            l_delta <= reduce_by;
            state   <= LVL_SCAN;
          end else begin
            state <= IDLE;                     // not our order: ignore
          end

          li           <= '0;
          l_match      <= 1'b0;
          l_free_found <= 1'b0;
        end

        // ---------------------------------------------------------
        LVL_SCAN: begin
          if (scan_valid && scan_price == l_price) begin
            l_match   <= 1'b1;
            l_match_i <= li;
          end
          if (!scan_valid && !l_free_found) begin
            l_free_found <= 1'b1;
            l_free_i     <= li;
          end

          if (li == LAST_LVL) state <= LVL_UPDATE;
          else                li    <= li + 1'b1;
        end

        // ---------------------------------------------------------
        LVL_UPDATE: begin
          if (l_match) begin
            if (l_add) begin
              lv_shares[l_side][l_match_i] <= match_shares + l_delta;
            end else begin
              lv_shares[l_side][l_match_i] <= match_shares - l_delta;
              if (match_shares == l_delta)
                lv_valid[l_side][l_match_i] <= 1'b0;   // level now empty
            end
          end else if (l_add && l_free_found) begin
            lv_valid [l_side][l_free_i] <= 1'b1;        // new price level
            lv_price [l_side][l_free_i] <= l_price;
            lv_shares[l_side][l_free_i] <= l_delta;
          end else if (l_add) begin
            err_lvl_full <= 1'b1;
          end else begin
            err_lvl_miss <= 1'b1;
          end

          li         <= '0;
          best_found <= 1'b0;
          state      <= BEST_SCAN;
        end

        // ---------------------------------------------------------
        BEST_SCAN: begin
          // bids: highest price wins. asks: lowest price wins.
          if (scan_valid &&
              (!best_found ||
               (l_side == BID && scan_price > best_p) ||
               (l_side == ASK && scan_price < best_p))) begin
            best_found <= 1'b1;
            best_p     <= scan_price;
            best_s     <= scan_shares;
          end

          if (li == LAST_LVL) state <= OUTPUT;
          else                li    <= li + 1'b1;
        end

        // ---------------------------------------------------------
        OUTPUT: begin
          if (l_side == BID) begin
            bid_price  <= best_found ? best_p : 32'd0;
            bid_shares <= best_found ? best_s : 32'd0;
          end else begin
            ask_price  <= best_found ? best_p : 32'd0;
            ask_shares <= best_found ? best_s : 32'd0;
          end
          tob_ts    <= cur_ts;
          tob_valid <= 1'b1;
          state     <= IDLE;
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule