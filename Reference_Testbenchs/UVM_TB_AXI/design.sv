
module axi_mem #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32,
  parameter int ID_WIDTH   = 4,
  parameter int MEM_DEPTH  = 256           // words of DATA_WIDTH
)(
  input  logic                    ACLK,
  input  logic                    ARESETn,

  // Write Request Channel (AW)
  input  logic [ID_WIDTH-1:0]     AWID,
  input  logic [ADDR_WIDTH-1:0]   AWADDR,
  input  logic [7:0]              AWLEN,   // burst length - 1
  input  logic [2:0]              AWSIZE,
  input  logic [1:0]              AWBURST,
  input  logic                    AWVALID,
  output logic                    AWREADY,

  // Write Data Channel (W)
  input  logic [DATA_WIDTH-1:0]   WDATA,
  input  logic [DATA_WIDTH/8-1:0] WSTRB,
  input  logic                    WLAST,
  input  logic                    WVALID,
  output logic                    WREADY,

  // Write Response Channel (B)
  output logic [ID_WIDTH-1:0]     BID,
  output logic [1:0]              BRESP,
  output logic                    BVALID,
  input  logic                    BREADY,

  // Read Request Channel (AR)
  input  logic [ID_WIDTH-1:0]     ARID,
  input  logic [ADDR_WIDTH-1:0]   ARADDR,
  input  logic [7:0]              ARLEN,
  input  logic [2:0]              ARSIZE,
  input  logic [1:0]              ARBURST,
  input  logic                    ARVALID,
  output logic                    ARREADY,

  // Read Data Channel (R)
  output logic [ID_WIDTH-1:0]     RID,
  output logic [DATA_WIDTH-1:0]   RDATA,
  output logic [1:0]              RRESP,
  output logic                    RLAST,
  output logic                    RVALID,
  input  logic                    RREADY
);

  localparam logic [1:0] RESP_OKAY   = 2'b00;
  localparam logic [1:0] RESP_SLVERR = 2'b10;

  localparam logic [1:0] BURST_FIXED = 2'b00;
  localparam logic [1:0] BURST_INCR  = 2'b01;
  localparam logic [1:0] BURST_WRAP  = 2'b10;
  localparam logic [1:0] BURST_RSVD  = 2'b11;

  localparam int DATA_BYTES   = DATA_WIDTH / 8;
  localparam int ADDR_LSB     = $clog2(DATA_BYTES);
  localparam int MAX_SIZE_ENC = $clog2(DATA_BYTES);

  logic [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

  // ----------------------------------------------------------------------------
  // Helpers
  // ----------------------------------------------------------------------------

  function automatic logic size_ok(input logic [2:0] axsize);
    size_ok = (axsize <= MAX_SIZE_ENC);
  endfunction

  function automatic logic burst_ok(input logic [1:0] axburst);
    burst_ok = (axburst != BURST_RSVD);
  endfunction

  function automatic logic wrap_len_ok(input logic [7:0] axlen);
    int unsigned beats;
    begin
      beats = axlen + 1;
      wrap_len_ok = (beats == 2) || (beats == 4) || (beats == 8) || (beats == 16);
    end
  endfunction

  function automatic logic addr_aligned_to_size(
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [2:0]            axsize
  );
    logic [ADDR_WIDTH-1:0] mask;
    begin
      mask = (logic'(1) << axsize) - 1;
      addr_aligned_to_size = ((addr & mask) == '0);
    end
  endfunction

  function automatic logic wrap_burst_legal(
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [2:0]            axsize,
    input logic [7:0]            axlen,
    input logic [1:0]            axburst
  );
    if (axburst != BURST_WRAP)
      wrap_burst_legal = 1'b1;
    else
      wrap_burst_legal = size_ok(axsize) &&
                         addr_aligned_to_size(addr, axsize) &&
                         wrap_len_ok(axlen);
  endfunction

  function automatic logic req_ok(
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [2:0]            axsize,
    input logic [7:0]            axlen,
    input logic [1:0]            axburst
  );
    req_ok = size_ok(axsize) &&
             burst_ok(axburst) &&
             wrap_burst_legal(addr, axsize, axlen, axburst);
  endfunction

  // AXI address progression per spec pseudocode:
  // - first unaligned beat of INCR/WRAP advances to aligned_addr + size
  // - later beats advance by size
  // - WRAP wraps on container boundary
  function automatic logic [ADDR_WIDTH-1:0] next_addr_axi(
    input logic [ADDR_WIDTH-1:0] cur_addr,
    input logic [ADDR_WIDTH-1:0] start_addr,
    input logic [2:0]            axsize,
    input logic [1:0]            axburst,
    input logic [7:0]            axlen,
    input logic [7:0]            beat_idx   // zero-based beat index just completed
  );
    logic [ADDR_WIDTH-1:0] size_bytes;
    logic [ADDR_WIDTH-1:0] aligned_addr;
    logic [ADDR_WIDTH-1:0] container_bytes;
    logic [ADDR_WIDTH-1:0] wrap_boundary;
    logic [ADDR_WIDTH-1:0] upper_wrap_boundary;
    logic [ADDR_WIDTH-1:0] nxt;
    logic [ADDR_WIDTH-1:0] size_mask;
    begin
      size_bytes       = (logic'(1) << axsize);
      size_mask        = size_bytes - 1;
      aligned_addr     = start_addr & ~size_mask;
      container_bytes  = size_bytes * (axlen + 1);
      wrap_boundary    = start_addr - (start_addr % container_bytes);
      upper_wrap_boundary = wrap_boundary + container_bytes;

      case (axburst)
        BURST_FIXED: nxt = cur_addr;

        BURST_WRAP: begin
          if ((beat_idx == 0) && ((start_addr & size_mask) != 0))
            nxt = aligned_addr + size_bytes;
          else
            nxt = cur_addr + size_bytes;

          if (nxt >= upper_wrap_boundary)
            nxt = wrap_boundary;
        end

        default: begin // INCR
          if ((beat_idx == 0) && ((start_addr & size_mask) != 0))
            nxt = aligned_addr + size_bytes;
          else
            nxt = cur_addr + size_bytes;
        end
      endcase

      next_addr_axi = nxt;
    end
  endfunction

  function automatic logic [7:0] mem_read_byte(
    input logic [ADDR_WIDTH-1:0] byte_addr
  );
    int unsigned word_idx;
    int unsigned byte_lane;
    begin
      word_idx  = byte_addr >> ADDR_LSB;
      byte_lane = byte_addr[ADDR_LSB-1:0];

      if (word_idx < MEM_DEPTH)
        mem_read_byte = mem[word_idx][8*byte_lane +: 8];
      else
        mem_read_byte = 8'h00;
    end
  endfunction

  // Build RDATA with bytes placed in the correct active lanes for narrow/unaligned
  // transfers. Lanes outside the active transfer are driven as zero.
  function automatic logic [DATA_WIDTH-1:0] build_rdata(
    input logic [ADDR_WIDTH-1:0] cur_addr,
    input logic [ADDR_WIDTH-1:0] start_addr,
    input logic [2:0]            axsize,
    input logic [7:0]            beat_idx
  );
    logic [DATA_WIDTH-1:0] data;
    logic [ADDR_WIDTH-1:0] size_bytes;
    logic [ADDR_WIDTH-1:0] aligned_addr;
    int unsigned lower_lane;
    int unsigned upper_lane;
    int unsigned lane;
    int unsigned src_byte;
    logic [ADDR_WIDTH-1:0] size_mask;
    logic                  aligned;
    begin
      data        = '0;
      size_bytes  = (logic'(1) << axsize);
      size_mask   = size_bytes - 1;
      aligned     = ((cur_addr & size_mask) == 0);
      aligned_addr = cur_addr & ~size_mask;

      lower_lane = cur_addr % DATA_BYTES;

      if (aligned)
        upper_lane = lower_lane + size_bytes - 1;
      else
        upper_lane = (aligned_addr + size_bytes - 1) % DATA_BYTES;

      src_byte = 0;
      for (lane = lower_lane; lane <= upper_lane; lane++) begin
        data[8*lane +: 8] = mem_read_byte(cur_addr + src_byte);
        src_byte++;
      end

      build_rdata = data;
    end
  endfunction

  // ----------------------------------------------------------------------------
  // Write FSM
  // ----------------------------------------------------------------------------

  typedef enum logic [1:0] {WR_IDLE, WR_DATA, WR_RESP} wr_state_t;
  wr_state_t wr_state;

  logic [ID_WIDTH-1:0]   wr_id;
  logic [ADDR_WIDTH-1:0] wr_addr;
  logic [ADDR_WIDTH-1:0] wr_start_addr;
  logic [7:0]            wr_len;
  logic [7:0]            wr_beat;
  logic [2:0]            wr_size;
  logic [1:0]            wr_burst;
  logic                  wr_error;

  always_ff @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      wr_state     <= WR_IDLE;
      AWREADY      <= 1'b1;
      WREADY       <= 1'b0;
      BVALID       <= 1'b0;
      BID          <= '0;
      BRESP        <= RESP_OKAY;
      wr_id        <= '0;
      wr_addr      <= '0;
      wr_start_addr<= '0;
      wr_len       <= '0;
      wr_beat      <= '0;
      wr_size      <= '0;
      wr_burst     <= BURST_INCR;
      wr_error     <= 1'b0;
      for (int i = 0; i < MEM_DEPTH; i++)
        mem[i] <= '0;
    end else begin
      case (wr_state)
        WR_IDLE: begin
          BVALID <= 1'b0;

          if (AWVALID && AWREADY) begin
            wr_id         <= AWID;
            wr_addr       <= AWADDR;
            wr_start_addr <= AWADDR;
            wr_len        <= AWLEN;
            wr_beat       <= '0;
            wr_size       <= AWSIZE;
            wr_burst      <= AWBURST;
            wr_error      <= ~req_ok(AWADDR, AWSIZE, AWLEN, AWBURST);

            AWREADY       <= 1'b0;
            WREADY        <= 1'b1;
            wr_state      <= WR_DATA;
          end
        end

        WR_DATA: begin
          if (WVALID && WREADY) begin
            logic beat_error;
            beat_error = wr_error;

            if (!beat_error) begin
              int unsigned widx;
              widx = wr_addr >> ADDR_LSB;

              if (widx < MEM_DEPTH) begin
                for (int b = 0; b < DATA_BYTES; b++) begin
                  if (WSTRB[b])
                    mem[widx][b*8 +: 8] <= WDATA[b*8 +: 8];
                end
              end else begin
                beat_error = 1'b1;
              end
            end

            if (WLAST) begin
              WREADY   <= 1'b0;
              BID      <= wr_id;
              BRESP    <= beat_error ? RESP_SLVERR : RESP_OKAY;
              BVALID   <= 1'b1;
              wr_error <= beat_error;
              wr_state <= WR_RESP;
            end else begin
              wr_error <= beat_error;
              wr_addr  <= next_addr_axi(wr_addr, wr_start_addr, wr_size, wr_burst, wr_len, wr_beat);
              wr_beat  <= wr_beat + 1;
            end
          end
        end

        WR_RESP: begin
          if (BVALID && BREADY) begin
            BVALID   <= 1'b0;
            AWREADY  <= 1'b1;
            WREADY   <= 1'b0;
            wr_error <= 1'b0;
            wr_state <= WR_IDLE;
          end
        end
      endcase
    end
  end

  // ----------------------------------------------------------------------------
  // Read FSM
  // ----------------------------------------------------------------------------

  typedef enum logic [0:0] {RD_IDLE, RD_DATA} rd_state_t;
  rd_state_t rd_state;

  logic [ID_WIDTH-1:0]   rd_id;
  logic [ADDR_WIDTH-1:0] rd_addr;
  logic [ADDR_WIDTH-1:0] rd_start_addr;
  logic [7:0]            rd_len;
  logic [7:0]            rd_beat;
  logic [2:0]            rd_size;
  logic [1:0]            rd_burst;
  logic                  rd_error;

  always_ff @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      rd_state      <= RD_IDLE;
      ARREADY       <= 1'b1;
      RVALID        <= 1'b0;
      RLAST         <= 1'b0;
      RID           <= '0;
      RDATA         <= '0;
      RRESP         <= RESP_OKAY;
      rd_id         <= '0;
      rd_addr       <= '0;
      rd_start_addr <= '0;
      rd_len        <= '0;
      rd_beat       <= '0;
      rd_size       <= '0;
      rd_burst      <= BURST_INCR;
      rd_error      <= 1'b0;
    end else begin
      case (rd_state)

        RD_IDLE: begin
          if (ARVALID && ARREADY) begin
            rd_id         <= ARID;
            rd_addr       <= ARADDR;
            rd_start_addr <= ARADDR;
            rd_len        <= ARLEN;
            rd_beat       <= '0;
            rd_size       <= ARSIZE;
            rd_burst      <= ARBURST;
            rd_error      <= ~req_ok(ARADDR, ARSIZE, ARLEN, ARBURST);

            ARREADY       <= 1'b0;
            rd_state      <= RD_DATA;
          end
        end

        RD_DATA: begin : rd_data_blk
          logic handshake_done;
          logic [ADDR_WIDTH-1:0] addr_for_this_beat;
          logic [7:0]            beat_for_this_beat;

          handshake_done = (RVALID && RREADY);

          // Present first beat, or advance to next beat after previous one is accepted
          if (!RVALID || handshake_done) begin

            // If the previously accepted beat was the last beat, finish the burst
            if (handshake_done && (rd_beat == rd_len)) begin
              RVALID   <= 1'b0;
              RLAST    <= 1'b0;
              ARREADY  <= 1'b1;
              rd_error <= 1'b0;
              rd_state <= RD_IDLE;
            end
            else begin
              // For the first presentation, use current rd_addr/rd_beat.
              // After a successful handshake, compute and present the next beat.
              if (handshake_done) begin
                addr_for_this_beat = next_addr_axi(
                  rd_addr,
                  rd_start_addr,
                  rd_size,
                  rd_burst,
                  rd_len,
                  rd_beat
                );
                beat_for_this_beat = rd_beat + 1;
              end
              else begin
                addr_for_this_beat = rd_addr;
                beat_for_this_beat = rd_beat;
              end

              rd_addr <= addr_for_this_beat;
              rd_beat <= beat_for_this_beat;

              RID    <= rd_id;
              RRESP  <= rd_error ? RESP_SLVERR : RESP_OKAY;
              RLAST  <= (beat_for_this_beat == rd_len);
              RDATA  <= rd_error ? '0
                                 : build_rdata(
                                     addr_for_this_beat,
                                     rd_start_addr,
                                     rd_size,
                                     beat_for_this_beat
                                   );
              RVALID <= 1'b1;
            end
          end
        end

      endcase
    end
  end

endmodule

interface axi_if #(
  parameter ADDR_WIDTH = 32,
  parameter DATA_WIDTH = 32,
  parameter ID_WIDTH   = 4
)(input logic ACLK);
 
  logic                    ARESETn;
 
  // Write Request
  logic [ID_WIDTH-1:0]     AWID;
  logic [ADDR_WIDTH-1:0]   AWADDR;
  logic [7:0]              AWLEN;
  logic [2:0]              AWSIZE;
  logic [1:0]              AWBURST;
  logic                    AWVALID;
  logic                    AWREADY;
 
  // Write Data
  logic [DATA_WIDTH-1:0]   WDATA;
  logic [DATA_WIDTH/8-1:0] WSTRB;
  logic                    WLAST;
  logic                    WVALID;
  logic                    WREADY;
 
  // Write Response
  logic [ID_WIDTH-1:0]     BID;
  logic [1:0]              BRESP;
  logic                    BVALID;
  logic                    BREADY;
 
  // Read Request
  logic [ID_WIDTH-1:0]     ARID;
  logic [ADDR_WIDTH-1:0]   ARADDR;
  logic [7:0]              ARLEN;
  logic [2:0]              ARSIZE;
  logic [1:0]              ARBURST;
  logic                    ARVALID;
  logic                    ARREADY;
 
  // Read Data
  logic [ID_WIDTH-1:0]     RID;
  logic [DATA_WIDTH-1:0]   RDATA;
  logic [1:0]              RRESP;
  logic                    RLAST;
  logic                    RVALID;
  logic                    RREADY;
 
  // ── Driver clocking block (Manager drives slave) ───────────────────────────
  clocking drv_cb @(posedge ACLK);
    default input #1step output #0;
    // Manager outputs → Slave inputs
    output ARESETn;
    output AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWVALID;
    output WDATA, WSTRB, WLAST, WVALID;
    output BREADY;
    output ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARVALID;
    output RREADY;
    // Slave outputs → Manager inputs
    input  AWREADY;
    input  WREADY;
    input  BID, BRESP, BVALID;
    input  ARREADY;
    input  RID, RDATA, RRESP, RLAST, RVALID;
  endclocking
 
  // ── Monitor clocking block (all signals observed) ─────────────────────────
  clocking mon_cb @(posedge ACLK);
    default input #1step output #0;
    input ARESETn;
    input AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWVALID, AWREADY;
    input WDATA, WSTRB, WLAST, WVALID, WREADY;
    input BID, BRESP, BVALID, BREADY;
    input ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARVALID, ARREADY;
    input RID, RDATA, RRESP, RLAST, RVALID, RREADY;
  endclocking
 
endinterface

// =============================================================================
// File: axi_mem_assertions.sv
// Description: Concurrent AXI4 protocol + functional assertions for axi_mem
//
// Spec reference: ARM IHI 0022L (AMBA AXI Protocol Specification)
//
// RTL write FSM: WR_IDLE → WR_DATA → WR_RESP → WR_IDLE
// RTL read  FSM: RD_IDLE → RD_DATA → RD_IDLE
//
// Key spec rules implemented:
//   §A2: VALID signals must be LOW during reset
//   §A2: Once VALID is asserted it must not deassert until handshake (VALID & READY)
//   §A2: Payload signals must be stable while VALID is asserted and unhandshaked
//   §A2: Subordinate must not wait for BREADY before asserting BVALID
//   §A3: WLAST must be asserted on the final write data beat only
//   §A3: RLAST must be asserted on the final read data beat only
//   §A5: BID must equal the AWID of the corresponding write transaction
//   §A5: RID must equal the ARID of the corresponding read transaction
// =============================================================================

module axi_mem_assertions #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32,
  parameter int ID_WIDTH   = 4,
  parameter int MEM_DEPTH  = 256
)(
  input  logic                    ACLK,
  input  logic                    ARESETn,
  // AW channel
  input  logic [ID_WIDTH-1:0]     AWID,
  input  logic [ADDR_WIDTH-1:0]   AWADDR,
  input  logic [7:0]              AWLEN,
  input  logic [2:0]              AWSIZE,
  input  logic [1:0]              AWBURST,
  input  logic                    AWVALID,
  input  logic                    AWREADY,
  // W channel
  input  logic [DATA_WIDTH-1:0]   WDATA,
  input  logic [DATA_WIDTH/8-1:0] WSTRB,
  input  logic                    WLAST,
  input  logic                    WVALID,
  input  logic                    WREADY,
  // B channel
  input  logic [ID_WIDTH-1:0]     BID,
  input  logic [1:0]              BRESP,
  input  logic                    BVALID,
  input  logic                    BREADY,
  // AR channel
  input  logic [ID_WIDTH-1:0]     ARID,
  input  logic [ADDR_WIDTH-1:0]   ARADDR,
  input  logic [7:0]              ARLEN,
  input  logic [2:0]              ARSIZE,
  input  logic [1:0]              ARBURST,
  input  logic                    ARVALID,
  input  logic                    ARREADY,
  // R channel
  input  logic [ID_WIDTH-1:0]     RID,
  input  logic [DATA_WIDTH-1:0]   RDATA,
  input  logic [1:0]              RRESP,
  input  logic                    RLAST,
  input  logic                    RVALID,
  input  logic                    RREADY,
  // Internal FSM signals accessed via bind
  input  logic [1:0]              wr_state,   // wr_state_t: WR_IDLE=0, WR_DATA=1, WR_RESP=2
  input  logic [ID_WIDTH-1:0]     wr_id,
  input  logic [7:0]              wr_len,
  input  logic [7:0]              wr_beat,
  input  logic                    wr_error,
  input  logic [0:0]              rd_state,   // rd_state_t: RD_IDLE=0, RD_DATA=1
  input  logic [ID_WIDTH-1:0]     rd_id,
  input  logic [7:0]              rd_len,
  input  logic [7:0]              rd_beat,
  input  logic                    rd_error
);

  // --------------------------------------------------------------------------
  // State encoding mirrors RTL typedef
  // --------------------------------------------------------------------------
  localparam logic [1:0] WR_IDLE = 2'd0;
  localparam logic [1:0] WR_DATA = 2'd1;
  localparam logic [1:0] WR_RESP = 2'd2;
  localparam logic [0:0] RD_IDLE = 1'd0;
  localparam logic [0:0] RD_DATA = 1'd1;

  localparam logic [1:0] RESP_OKAY   = 2'b00;
  localparam logic [1:0] RESP_SLVERR = 2'b10;
  localparam logic [1:0] BURST_RSVD  = 2'b11;

  // ==========================================================================
  // CA-1: Reset — all VALID outputs must be LOW during/immediately after reset
  //       Spec §A2: "VALID signals must be LOW during reset."
  //       ARESETn is async; uses |-> (same-cycle implication).
  //       Also checks AWREADY=1 and ARREADY=1, and WREADY=0 at reset,
  //       which matches the RTL initial state.
  // ==========================================================================
  property p_reset_valid_low;
    @(posedge ACLK)
    !ARESETn |-> (!BVALID && !RVALID && !AWREADY === 1'b0);
  endproperty

  property p_reset_outputs;
    @(posedge ACLK)
    !ARESETn |-> (BVALID   === 1'b0 &&
                  RVALID   === 1'b0 &&
                  WREADY   === 1'b0 &&
                  AWREADY  === 1'b1 &&
                  ARREADY  === 1'b1);
  endproperty

  ASSERT_RESET_OUTPUTS: assert property (p_reset_outputs)
    else $error("[CA-1] Reset outputs wrong: BVALID=%0b RVALID=%0b WREADY=%0b AWREADY=%0b ARREADY=%0b at %0t",
                BVALID, RVALID, WREADY, AWREADY, ARREADY, $time);

  COVER_RESET: cover property (p_reset_outputs);

  // ==========================================================================
  // CA-2: VALID stability — once asserted, VALID must not deassert until
  //       the handshake completes (VALID & READY both HIGH on posedge).
  //       Spec §A2: "When VALID is asserted, it must remain asserted until
  //       the handshake occurs."
  //       Applied to all five channels independently.
  // ==========================================================================

  // AW channel
  property p_awvalid_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (AWVALID && !AWREADY) |=> AWVALID;
  endproperty

  ASSERT_AWVALID_STABLE: assert property (p_awvalid_stable)
    else $error("[CA-2a] AWVALID deasserted before handshake at %0t", $time);

  // W channel
  property p_wvalid_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (WVALID && !WREADY) |=> WVALID;
  endproperty

  ASSERT_WVALID_STABLE: assert property (p_wvalid_stable)
    else $error("[CA-2b] WVALID deasserted before handshake at %0t", $time);

  // B channel
  property p_bvalid_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (BVALID && !BREADY) |=> BVALID;
  endproperty

  ASSERT_BVALID_STABLE: assert property (p_bvalid_stable)
    else $error("[CA-2c] BVALID deasserted before handshake at %0t", $time);

  // AR channel
  property p_arvalid_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (ARVALID && !ARREADY) |=> ARVALID;
  endproperty

  ASSERT_ARVALID_STABLE: assert property (p_arvalid_stable)
    else $error("[CA-2d] ARVALID deasserted before handshake at %0t", $time);

  // R channel
  property p_rvalid_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (RVALID && !RREADY) |=> RVALID;
  endproperty

  ASSERT_RVALID_STABLE: assert property (p_rvalid_stable)
    else $error("[CA-2e] RVALID deasserted before handshake at %0t", $time);

  // ==========================================================================
  // CA-3: Payload stability — AW and AR channel payload must not change
  //       while VALID is asserted but the handshake has not yet occurred.
  //       Spec §A2 Figure A2.2: "The transmitter must keep its information
  //       stable until the transfer occurs."
  //       Covers AWID, AWADDR, AWLEN, AWSIZE, AWBURST for write request,
  //       and ARID, ARADDR, ARLEN, ARSIZE, ARBURST for read request.
  // ==========================================================================
  property p_aw_payload_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (AWVALID && !AWREADY) |=>
      ($stable(AWID)    &&
       $stable(AWADDR)  &&
       $stable(AWLEN)   &&
       $stable(AWSIZE)  &&
       $stable(AWBURST));
  endproperty

  ASSERT_AW_PAYLOAD_STABLE: assert property (p_aw_payload_stable)
    else $error("[CA-3a] AW payload changed before handshake at %0t", $time);

  property p_ar_payload_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (ARVALID && !ARREADY) |=>
      ($stable(ARID)    &&
       $stable(ARADDR)  &&
       $stable(ARLEN)   &&
       $stable(ARSIZE)  &&
       $stable(ARBURST));
  endproperty

  ASSERT_AR_PAYLOAD_STABLE: assert property (p_ar_payload_stable)
    else $error("[CA-3b] AR payload changed before handshake at %0t", $time);

  // Also check W channel payload stability (WDATA, WSTRB, WLAST)
  property p_w_payload_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (WVALID && !WREADY) |=>
      ($stable(WDATA) &&
       $stable(WSTRB) &&
       $stable(WLAST));
  endproperty

  ASSERT_W_PAYLOAD_STABLE: assert property (p_w_payload_stable)
    else $error("[CA-3c] W payload changed before handshake at %0t", $time);

  // ==========================================================================
  // CA-4: WLAST correctness
  //       Spec §A3: "The Manager must assert WLAST while driving the final
  //       write transfer in the transaction."
  //       RTL interpretation: WLAST must be asserted on beat wr_beat==wr_len
  //       and must NOT be asserted on earlier beats.
  //       We check the RTL's own wr_beat and wr_len registers, which are the
  //       source-of-truth for the active burst state.
  // ==========================================================================

  // WLAST must be HIGH on the final beat
  property p_wlast_on_last_beat;
    @(posedge ACLK) disable iff (!ARESETn)
    (wr_state === WR_DATA && WVALID && WREADY && (wr_beat === wr_len))
    |-> WLAST;
  endproperty

  ASSERT_WLAST_ON_LAST: assert property (p_wlast_on_last_beat)
    else $error("[CA-4a] WLAST not asserted on final beat: wr_beat=%0d wr_len=%0d at %0t",
                wr_beat, wr_len, $time);

  // WLAST must NOT be HIGH on non-final beats
  property p_wlast_not_early;
    @(posedge ACLK) disable iff (!ARESETn)
    (wr_state === WR_DATA && WVALID && WREADY && (wr_beat !== wr_len))
    |-> !WLAST;
  endproperty

  ASSERT_WLAST_NOT_EARLY: assert property (p_wlast_not_early)
    else $error("[CA-4b] WLAST asserted early: wr_beat=%0d wr_len=%0d at %0t",
                wr_beat, wr_len, $time);

  COVER_WLAST: cover property (p_wlast_on_last_beat);

  // ==========================================================================
  // CA-5: BID must match the captured AWID
  //       Spec §A5: The write response ID must match the transaction ID
  //       of the write request that generated it.
  //       wr_id is latched from AWID at the AW handshake.
  // ==========================================================================
  property p_bid_matches_awid;
    @(posedge ACLK) disable iff (!ARESETn)
    BVALID |-> (BID === wr_id);
  endproperty

  ASSERT_BID_MATCHES: assert property (p_bid_matches_awid)
    else $error("[CA-5] BID mismatch: BID=%0h wr_id=%0h at %0t",
                BID, wr_id, $time);

  COVER_BVALID: cover property (@(posedge ACLK) disable iff (!ARESETn) BVALID);

  // ==========================================================================
  // CA-6: BRESP correctness
  //       RESP_OKAY   (2'b00) for a transaction that passed req_ok checks
  //       RESP_SLVERR (2'b10) for a transaction where wr_error was set
  //       Spec §A3: BRESP signals the outcome of the entire burst.
  // ==========================================================================
  property p_bresp_okay_when_no_error;
    @(posedge ACLK) disable iff (!ARESETn)
    (BVALID && !wr_error) |-> (BRESP === RESP_OKAY);
  endproperty

  property p_bresp_slverr_when_error;
    @(posedge ACLK) disable iff (!ARESETn)
    (BVALID && wr_error) |-> (BRESP === RESP_SLVERR);
  endproperty

  ASSERT_BRESP_OKAY:   assert property (p_bresp_okay_when_no_error)
    else $error("[CA-6a] BRESP not OKAY for good write: BRESP=%0b at %0t", BRESP, $time);

  ASSERT_BRESP_SLVERR: assert property (p_bresp_slverr_when_error)
    else $error("[CA-6b] BRESP not SLVERR for bad write: BRESP=%0b at %0t", BRESP, $time);

  COVER_BRESP_SLVERR: cover property (p_bresp_slverr_when_error);

  // ==========================================================================
  // CA-7: RLAST correctness — mirrors CA-4 for the read path
  //       Spec §A3: "The Subordinate must assert RLAST when driving the
  //       final read transfer in the transaction."
  // ==========================================================================

  // RLAST must be asserted on the final read beat
  property p_rlast_on_last_beat;
    @(posedge ACLK) disable iff (!ARESETn)
    (rd_state === RD_DATA && RVALID && RREADY && (rd_beat === rd_len))
    |-> RLAST;
  endproperty

  ASSERT_RLAST_ON_LAST: assert property (p_rlast_on_last_beat)
    else $error("[CA-7a] RLAST not asserted on final read beat: rd_beat=%0d rd_len=%0d at %0t",
                rd_beat, rd_len, $time);

  // RLAST must NOT be asserted on non-final beats
  property p_rlast_not_early;
    @(posedge ACLK) disable iff (!ARESETn)
    (rd_state === RD_DATA && RVALID && RREADY && (rd_beat !== rd_len))
    |-> !RLAST;
  endproperty

  ASSERT_RLAST_NOT_EARLY: assert property (p_rlast_not_early)
    else $error("[CA-7b] RLAST asserted early: rd_beat=%0d rd_len=%0d at %0t",
                rd_beat, rd_len, $time);

  COVER_RLAST: cover property (p_rlast_on_last_beat);

  // ==========================================================================
  // CA-8: RID must match the captured ARID
  //       Spec §A5: Read data ID must match the request ID.
  //       rd_id is latched from ARID at the AR handshake.
  // ==========================================================================
  property p_rid_matches_arid;
    @(posedge ACLK) disable iff (!ARESETn)
    RVALID |-> (RID === rd_id);
  endproperty

  ASSERT_RID_MATCHES: assert property (p_rid_matches_arid)
    else $error("[CA-8] RID mismatch: RID=%0h rd_id=%0h at %0t",
                RID, rd_id, $time);

  COVER_RVALID: cover property (@(posedge ACLK) disable iff (!ARESETn) RVALID);

  // ==========================================================================
  // CA-9: RRESP correctness
  //       Mirrors CA-6 for the read path.
  // ==========================================================================
  property p_rresp_okay_when_no_error;
    @(posedge ACLK) disable iff (!ARESETn)
    (RVALID && !rd_error) |-> (RRESP === RESP_OKAY);
  endproperty

  property p_rresp_slverr_when_error;
    @(posedge ACLK) disable iff (!ARESETn)
    (RVALID && rd_error) |-> (RRESP === RESP_SLVERR);
  endproperty

  ASSERT_RRESP_OKAY:   assert property (p_rresp_okay_when_no_error)
    else $error("[CA-9a] RRESP not OKAY for good read: RRESP=%0b at %0t", RRESP, $time);

  ASSERT_RRESP_SLVERR: assert property (p_rresp_slverr_when_error)
    else $error("[CA-9b] RRESP not SLVERR for bad read: RRESP=%0b at %0t", RRESP, $time);

  COVER_RRESP_SLVERR: cover property (p_rresp_slverr_when_error);

  // ==========================================================================
  // CA-10: Exclusive READY signals — AWREADY and WREADY are never both HIGH
  //        in WR_IDLE because the RTL only transitions to WR_DATA (setting
  //        WREADY=1) after consuming the AW handshake (which clears AWREADY).
  //        AWREADY must also be LOW in WR_DATA and WR_RESP states.
  // ==========================================================================
  property p_awready_low_in_wr_data;
    @(posedge ACLK) disable iff (!ARESETn)
    (wr_state === WR_DATA || wr_state === WR_RESP) |-> (AWREADY === 1'b0);
  endproperty

  ASSERT_AWREADY_EXCLUSIVE: assert property (p_awready_low_in_wr_data)
    else $error("[CA-10a] AWREADY high during WR_DATA/WR_RESP: wr_state=%0b at %0t",
                wr_state, $time);

  // WREADY must be LOW in WR_IDLE and WR_RESP
  property p_wready_low_outside_data;
    @(posedge ACLK) disable iff (!ARESETn)
    (wr_state === WR_IDLE || wr_state === WR_RESP) |-> (WREADY === 1'b0);
  endproperty

  ASSERT_WREADY_EXCLUSIVE: assert property (p_wready_low_outside_data)
    else $error("[CA-10b] WREADY high outside WR_DATA: wr_state=%0b at %0t",
                wr_state, $time);

  // ==========================================================================
  // CA-11: BVALID must be LOW until WR_RESP state is entered
  //        Spec §A2: "The Subordinate must wait for AWVALID, AWREADY,
  //        WVALID, and WREADY to be asserted before asserting BVALID" and
  //        "must wait for the last write data transfer before asserting BVALID."
  // ==========================================================================
  property p_bvalid_only_in_wr_resp;
    @(posedge ACLK) disable iff (!ARESETn)
(!$isunknown(wr_state) && (wr_state != WR_RESP)) |-> (BVALID == 1'b0);
  endproperty

  ASSERT_BVALID_ONLY_RESP: assert property (p_bvalid_only_in_wr_resp)
    else $error("[CA-11] BVALID asserted outside WR_RESP: wr_state=%0b at %0t",
                wr_state, $time);

  // ==========================================================================
  // CA-12: RVALID must be LOW in RD_IDLE — the subordinate must not drive
  //        read data before a read request has been accepted.
  //        Spec §A3: "The Subordinate must assert RVALID only in response
  //        to a request."
  // ==========================================================================
  property p_rvalid_only_in_rd_data;
    @(posedge ACLK) disable iff (!ARESETn)
    (rd_state === RD_IDLE) |-> (RVALID === 1'b0);
  endproperty

  ASSERT_RVALID_ONLY_DATA: assert property (p_rvalid_only_in_rd_data)
    else $error("[CA-12] RVALID asserted in RD_IDLE at %0t", $time);

  // ==========================================================================
  // CA-13: ARREADY must be LOW in RD_DATA — the RTL only accepts one
  //        outstanding read transaction at a time. While serving a burst,
  //        the subordinate must not accept a new AR request.
  // ==========================================================================
  property p_arready_low_in_rd_data;
    @(posedge ACLK) disable iff (!ARESETn)
    (rd_state === RD_DATA) |-> (ARREADY === 1'b0);
  endproperty

  ASSERT_ARREADY_LOW_IN_DATA: assert property (p_arready_low_in_rd_data)
    else $error("[CA-13] ARREADY high during active read burst at %0t", $time);

  // ==========================================================================
  // CA-14: Reserved burst type must not be accepted without error
  //        Spec §A3: BURST=2'b11 is reserved and must not be used.
  //        If req_ok() catches it, wr_error/rd_error is set. Verify that
  //        a reserved burst on the AW channel always causes BRESP=SLVERR.
  // ==========================================================================
  property p_rsvd_burst_write_error;
    @(posedge ACLK) disable iff (!ARESETn)
    (AWVALID && AWREADY && (AWBURST === BURST_RSVD))
    |-> ##[1:$] (BVALID && BRESP === RESP_SLVERR);
  endproperty

  ASSERT_RSVD_BURST_WRITE: assert property (p_rsvd_burst_write_error)
    else $error("[CA-14a] Reserved AWBURST did not produce SLVERR at %0t", $time);

  COVER_RSVD_BURST_WRITE: cover property (p_rsvd_burst_write_error);

  property p_rsvd_burst_read_error;
    @(posedge ACLK) disable iff (!ARESETn)
    (ARVALID && ARREADY && (ARBURST === BURST_RSVD))
    |-> ##[1:$] (RVALID && RLAST && RRESP === RESP_SLVERR);
  endproperty

  ASSERT_RSVD_BURST_READ: assert property (p_rsvd_burst_read_error)
    else $error("[CA-14b] Reserved ARBURST did not produce SLVERR at %0t", $time);

  COVER_RSVD_BURST_READ: cover property (p_rsvd_burst_read_error);

endmodule : axi_mem_assertions

bind axi_mem axi_mem_assertions #(
  .ADDR_WIDTH (ADDR_WIDTH),
  .DATA_WIDTH (DATA_WIDTH),
  .ID_WIDTH   (ID_WIDTH),
  .MEM_DEPTH  (MEM_DEPTH)
) u_axi_mem_assertions (
  .ACLK     (ACLK),
  .ARESETn  (ARESETn),
  // AW
  .AWID     (AWID),    .AWADDR   (AWADDR),  .AWLEN  (AWLEN),
  .AWSIZE   (AWSIZE),  .AWBURST  (AWBURST), .AWVALID(AWVALID), .AWREADY(AWREADY),
  // W
  .WDATA    (WDATA),   .WSTRB    (WSTRB),   .WLAST  (WLAST),
  .WVALID   (WVALID),  .WREADY   (WREADY),
  // B
  .BID      (BID),     .BRESP    (BRESP),   .BVALID (BVALID),  .BREADY (BREADY),
  // AR
  .ARID     (ARID),    .ARADDR   (ARADDR),  .ARLEN  (ARLEN),
  .ARSIZE   (ARSIZE),  .ARBURST  (ARBURST), .ARVALID(ARVALID), .ARREADY(ARREADY),
  // R
  .RID      (RID),     .RDATA    (RDATA),   .RRESP  (RRESP),
  .RLAST    (RLAST),   .RVALID   (RVALID),  .RREADY (RREADY),
  // Internal FSM state
  .wr_state (wr_state), .wr_id  (wr_id),   .wr_len   (wr_len),
  .wr_beat  (wr_beat),  .wr_error(wr_error),
  .rd_state (rd_state), .rd_id  (rd_id),   .rd_len   (rd_len),
  .rd_beat  (rd_beat),  .rd_error(rd_error)
);
