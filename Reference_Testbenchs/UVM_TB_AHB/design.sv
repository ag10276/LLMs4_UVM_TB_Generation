module ahb_mem(
  input logic HRESETn,
  input logic HCLK,
  
  input logic HSEL,
  input logic [31:0] HADDR,
  input logic HWRITE,
  input logic [1:0] HTRANS,
  
  input logic [2:0] HSIZE,
  input logic [2:0] HBURST,
  input logic HREADY,
  
  input logic [31:0] HWDATA,
  
  output logic [31:0] HRDATA,
  output logic HREADYOUT,
  output logic HRESP
);
  
  logic [31:0] mem [31:0];
  
  localparam logic [1:0] IDLE = 2'b00, NONSEQ = 2'b10, SEQ = 2'b11;
  localparam logic [2:0] HSIZE_BYTE = 3'b000, HSIZE_HALF = 3'b001, HSIZE_WORD = 3'b010;
  
  typedef enum logic [1:0] {ST_OKAY, ST_ERR1, ST_ERR2} resp_state_t;
  resp_state_t r_state;
  
  
  logic s_hsel;
  logic s_hwrite;
  logic [1:0] s_htrans;
  logic [2:0] s_hsize;
  logic [2:0] s_hburst;
  logic [31:0] s_haddr;
 
  logic [4:0] word_idx;
  
  logic size_supported;
  logic aligned_ok;
  logic access_ok;
  logic valid_transfer;
  logic access_error;
  
  logic [31:0] mem_rdata;
  logic [31:0] write_data_next;
  
  assign valid_transfer = s_hsel && (s_htrans == NONSEQ || s_htrans == SEQ);
  assign word_idx = s_haddr[6:2];
  assign mem_rdata = mem[word_idx];
  assign size_supported = (s_hsize == HSIZE_BYTE) || (s_hsize == HSIZE_HALF) || (s_hsize == HSIZE_WORD);
  assign access_ok = valid_transfer && size_supported && aligned_ok;
  assign access_error = valid_transfer && (!size_supported || !aligned_ok);
  
 //address phase and error handling
  always_ff @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) begin
      s_hsel   <= 1'b0;
      s_haddr  <= '0;
      s_hwrite <= 1'b0;
      s_htrans <= IDLE;
      s_hsize  <= HSIZE_WORD;
      s_hburst <= 3'b000;
      r_state  <= ST_OKAY;
    end else begin
      case (r_state)
        ST_OKAY: begin
          if (HREADY) begin
            s_hsel   <= HSEL;
            s_haddr  <= HADDR;
            s_hwrite <= HWRITE;
            s_htrans <= HTRANS;
            s_hsize  <= HSIZE;
            s_hburst <= HBURST;
            if (HSEL && (HTRANS == NONSEQ || HTRANS == SEQ)) begin
               if (!((HSIZE <= HSIZE_WORD) && 
                 ((HSIZE == HSIZE_BYTE) || (HSIZE == HSIZE_HALF && HADDR[0] == 0) || (HSIZE == HSIZE_WORD && HADDR[1:0] == 0))))
                 r_state <= ST_ERR1;
            end
          end
        end
        ST_ERR1: r_state <= ST_ERR2; 
        ST_ERR2: r_state <= ST_OKAY; 
      endcase
    end
  end
  
  //mem write
  always_ff @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) begin
      for (int i = 0; i < 32; i++) 
        mem[i] <= '0;
    end
    else if (access_ok && s_hwrite && (r_state == ST_OKAY) ) begin
      mem[word_idx] <= write_data_next;
    end
  end
  
  //check alignment
  always_comb begin
    aligned_ok = 1'b0;
    unique case (s_hsize)
      HSIZE_BYTE: aligned_ok = 1'b1;
      HSIZE_HALF: aligned_ok = (s_haddr[0]   == 1'b0);
      HSIZE_WORD: aligned_ok = (s_haddr[1:0] == 2'b00);
      default:    aligned_ok = 1'b0;
    endcase
  end
  
  //hsize and write handling
  always_comb begin
    write_data_next = mem_rdata;
    unique case (s_hsize)
      HSIZE_BYTE: begin
        unique case (s_haddr[1:0])
          2'b00: write_data_next[7:0]   = HWDATA[7:0];
          2'b01: write_data_next[15:8]  = HWDATA[7:0];
          2'b10: write_data_next[23:16] = HWDATA[7:0];
          2'b11: write_data_next[31:24] = HWDATA[7:0];
        endcase
      end
      HSIZE_HALF: begin
        unique case (s_haddr[1])
          1'b0: write_data_next[15:0]  = HWDATA[15:0];
          1'b1: write_data_next[31:16] = HWDATA[15:0];
        endcase
      end
      HSIZE_WORD: begin
        write_data_next = HWDATA;
      end
      default: begin
        write_data_next = mem_rdata;
      end
    endcase
  end
  
  //response and read handling
  always_comb begin
    HRESP = 1'b0; 
    HREADYOUT = 1'b1; 
    HRDATA = '0; 

    case (r_state)
      ST_ERR1: begin
        HRESP = 1'b1; 
        HREADYOUT = 1'b0;
      end
      ST_ERR2: begin
        HRESP = 1'b1; 
        HREADYOUT = 1'b1; 
      end
      default: begin
        if (access_ok && !s_hwrite) begin
          unique case (s_hsize)
            HSIZE_BYTE: begin
              unique case (s_haddr[1:0])
                2'b00: HRDATA[7:0] = mem_rdata[7:0];
                2'b01: HRDATA[7:0] = mem_rdata[15:8];
                2'b10: HRDATA[7:0] = mem_rdata[23:16];
                2'b11: HRDATA[7:0] = mem_rdata[31:24];
              endcase
            end
            HSIZE_HALF: begin
              unique case (s_haddr[1])
                1'b0: HRDATA[15:0] = mem_rdata[15:0];
                1'b1: HRDATA[15:0] = mem_rdata[31:16];
              endcase
            end
            HSIZE_WORD: begin
              HRDATA = mem_rdata;
            end
            default: begin
              HRDATA = '0;
            end
          endcase
        end
      end
    endcase
  end
  
endmodule

interface ahb_if(input logic HCLK);
  logic HRESETn;
  logic HSEL;
  logic [31:0] HADDR;
  logic HWRITE;
  logic [1:0] HTRANS;
  logic [2:0] HSIZE;
  logic [2:0] HBURST;
  logic HREADY;
  logic [31:0] HWDATA;
  logic [31:0] HRDATA;
  logic HREADYOUT;
  logic HRESP;
  
  clocking drv_cb @(posedge HCLK);
    default input #1step output #0;
    output HRESETn, HSEL, HADDR, HWRITE, HTRANS, HSIZE, HBURST, HREADY, HWDATA;
    input  HRDATA, HREADYOUT, HRESP;
  endclocking

  clocking mon_cb @(posedge HCLK);
    default input #1step output #0;
    input HRESETn, HSEL, HADDR, HWRITE, HTRANS, HSIZE, HBURST,
          HREADY, HWDATA, HRDATA, HREADYOUT, HRESP;
  endclocking
endinterface

// =============================================================================
// File: ahb_mem_assertions.sv
// Description: Concurrent AHB protocol + functional assertions for ahb_mem
//
// Spec reference: ARM IHI 0033C (AMBA AHB Protocol Specification)
//
// Key AHB pipeline insight:
//   AHB is a PIPELINED bus. HADDR/HWRITE/HTRANS/HSIZE are the ADDRESS phase
//   and are captured into s_h* registers on the posedge HCLK when HREADY=1.
//   HWDATA/HRDATA/HRESP/HREADYOUT are the DATA phase and apply to the
//   PREVIOUSLY captured address. Assertions must respect this pipeline split.
//
// Error FSM (RTL internal):
//   ST_OKAY  → normal operation: HRESP=0, HREADYOUT=1
//   ST_ERR1  → first error cycle:  HRESP=1, HREADYOUT=0  (spec §5.1.3)
//   ST_ERR2  → second error cycle: HRESP=1, HREADYOUT=1  (spec §5.1.3)
//   ST_ERR2  → ST_OKAY unconditionally next cycle
//
// Error trigger:
//   Misaligned access OR unsupported HSIZE (>WORD) on a NONSEQ/SEQ transfer
//   while HSEL is asserted and HREADY is HIGH.
// =============================================================================

module ahb_mem_assertions (
  input logic        HRESETn,
  input logic        HCLK,
  input logic        HSEL,
  input logic [31:0] HADDR,
  input logic        HWRITE,
  input logic [1:0]  HTRANS,
  input logic [2:0]  HSIZE,
  input logic [2:0]  HBURST,
  input logic        HREADY,
  input logic [31:0] HWDATA,
  input logic [31:0] HRDATA,
  input logic        HREADYOUT,
  input logic        HRESP,
  // Internal signals accessed via bind
  input logic [1:0]  r_state,
  input logic        s_hsel,
  input logic [31:0] s_haddr,
  input logic        s_hwrite,
  input logic [1:0]  s_htrans,
  input logic [2:0]  s_hsize,
  input logic        valid_transfer,
  input logic        access_ok,
  input logic        access_error
);

  // --------------------------------------------------------------------------
  // Local parameter aliases – mirror RTL localparams
  // --------------------------------------------------------------------------
  localparam logic [1:0] HTRANS_IDLE   = 2'b00;
  localparam logic [1:0] HTRANS_NONSEQ = 2'b10;
  localparam logic [1:0] HTRANS_SEQ    = 2'b11;

  localparam logic [2:0] HSIZE_BYTE = 3'b000;
  localparam logic [2:0] HSIZE_HALF = 3'b001;
  localparam logic [2:0] HSIZE_WORD = 3'b010;

  localparam logic [1:0] ST_OKAY = 2'b00;
  localparam logic [1:0] ST_ERR1 = 2'b01;
  localparam logic [1:0] ST_ERR2 = 2'b10;

  // ==========================================================================
  // CA-1: Reset
  //       Spec §3 (reset section): After HRESETn de-asserts the interface
  //       must be in a quiescent state. RTL resets s_htrans to IDLE,
  //       r_state to ST_OKAY, and all sampled address signals to 0.
  //       Uses |-> (same-cycle) because HRESETn is asynchronous and the
  //       combinational outputs resolve immediately from r_state.
  // ==========================================================================
  property p_reset;
    @(posedge HCLK)
    !HRESETn |-> (r_state  === ST_OKAY       &&
                  s_htrans === HTRANS_IDLE    &&
                  HRESP    === 1'b0           &&
                  HREADYOUT === 1'b1);
  endproperty

  ASSERT_RESET: assert property (p_reset)
    else $error("[CA-1] Reset state wrong: r_state=%0b s_htrans=%0b HRESP=%0b HREADYOUT=%0b at %0t",
                r_state, s_htrans, HRESP, HREADYOUT, $time);

  COVER_RESET: cover property (p_reset);

  // ==========================================================================
  // CA-2: Address phase stability during wait states
  //       Spec §3.7: When HREADY is LOW the Manager must not change the
  //       address-phase signals. The RTL only latches s_h* when HREADY=1,
  //       so this assertion validates the input discipline from the Manager.
  // ==========================================================================
  property p_addr_stable_during_wait;
    @(posedge HCLK) disable iff (!HRESETn)
    (!HREADY && HSEL &&
     (HTRANS === HTRANS_NONSEQ || HTRANS === HTRANS_SEQ))
    |=> ($stable(HADDR)  &&
         $stable(HTRANS) &&
         $stable(HWRITE) &&
         $stable(HSIZE));
  endproperty

  ASSERT_ADDR_STABLE: assert property (p_addr_stable_during_wait)
    else $error("[CA-2] Address-phase signals changed during HREADY=0 at %0t", $time);

  // ==========================================================================
  // CA-3: Error trigger – misaligned or unsupported size enters ST_ERR1
  //       Spec §5.1.3: A Subordinate must signal an error using the two-cycle
  //       error response. The RTL transitions to ST_ERR1 when the incoming
  //       address-phase signals (before sampling) indicate a bad access.
  //       Checked on the address phase input signals, one cycle before
  //       the s_h* registers capture them.
  // ==========================================================================
  property p_error_trigger;
    @(posedge HCLK) disable iff (!HRESETn)
    // Condition: a real transfer arrives with bad alignment/size while HREADY=1
    (r_state === ST_OKAY && HREADY && HSEL &&
     (HTRANS === HTRANS_NONSEQ || HTRANS === HTRANS_SEQ) &&
     !((HSIZE <= HSIZE_WORD) &&
       ((HSIZE == HSIZE_BYTE) ||
        (HSIZE == HSIZE_HALF && HADDR[0] == 1'b0) ||
        (HSIZE == HSIZE_WORD && HADDR[1:0] == 2'b00))))
    |=> (r_state === ST_ERR1);
  endproperty

  ASSERT_ERROR_TRIGGER: assert property (p_error_trigger)
    else $error("[CA-3] Bad access did not enter ST_ERR1: r_state=%0b HADDR=%0h HSIZE=%0b at %0t",
                r_state, HADDR, HSIZE, $time);

  COVER_ERROR_TRIGGER: cover property (p_error_trigger);

  // ==========================================================================
  // CA-4a: Two-cycle error – ST_ERR1 must always advance to ST_ERR2
  //        Spec §5.1.3 Table 5-2: First error cycle: HRESP=1, HREADYOUT=0.
  //        The transition to ST_ERR2 is unconditional (no HREADY dependency).
  // ==========================================================================
  property p_err1_to_err2;
    @(posedge HCLK) disable iff (!HRESETn)
    (r_state === ST_ERR1) |=> (r_state === ST_ERR2);
  endproperty

  ASSERT_ERR1_TO_ERR2: assert property (p_err1_to_err2)
    else $error("[CA-4a] ST_ERR1 did not advance to ST_ERR2 at %0t", $time);

  COVER_ERR1_TO_ERR2: cover property (p_err1_to_err2);

  // ==========================================================================
  // CA-4b: Two-cycle error – ST_ERR2 must always return to ST_OKAY
  //        Spec §5.1.3 Table 5-2: Second error cycle: HRESP=1, HREADYOUT=1.
  //        After this the bus is back to normal operation.
  // ==========================================================================
  property p_err2_to_okay;
    @(posedge HCLK) disable iff (!HRESETn)
    (r_state === ST_ERR2) |=> (r_state === ST_OKAY);
  endproperty

  ASSERT_ERR2_TO_OKAY: assert property (p_err2_to_okay)
    else $error("[CA-4b] ST_ERR2 did not return to ST_OKAY at %0t", $time);

  COVER_ERR2_TO_OKAY: cover property (p_err2_to_okay);

  // ==========================================================================
  // CA-5: Valid write – no error response for a good write access
  //       access_ok = valid_transfer && size_supported && aligned_ok (RTL)
  //       In ST_OKAY with a valid write, HRESP must stay 0 and HREADYOUT=1.
  //       NOTE: checks the DATA phase (s_h* signals), not the incoming bus.
  // ==========================================================================
  property p_valid_write_ok_response;
    @(posedge HCLK) disable iff (!HRESETn)
    (r_state === ST_OKAY && access_ok && s_hwrite)
    |-> (HRESP === 1'b0 && HREADYOUT === 1'b1);
  endproperty

  ASSERT_VALID_WRITE_OK: assert property (p_valid_write_ok_response)
    else $error("[CA-5] Valid write got error response: HRESP=%0b HREADYOUT=%0b at %0t",
                HRESP, HREADYOUT, $time);

  COVER_VALID_WRITE_OK: cover property (p_valid_write_ok_response);

  // ==========================================================================
  // CA-6: Valid read – no error response and HRDATA must be defined
  //       Spec Appendix A: HRDATA is valid at the end of a read transfer.
  //       Checks data phase: s_hwrite=0, access_ok=1, r_state=ST_OKAY.
  // ==========================================================================
  property p_valid_read_ok_response;
    @(posedge HCLK) disable iff (!HRESETn)
    (r_state === ST_OKAY && access_ok && !s_hwrite)
    |-> (HRESP === 1'b0 && HREADYOUT === 1'b1 && !$isunknown(HRDATA));
  endproperty

  ASSERT_VALID_READ_OK: assert property (p_valid_read_ok_response)
    else $error("[CA-6] Valid read got bad response: HRESP=%0b HREADYOUT=%0b HRDATA=%0h at %0t",
                HRESP, HREADYOUT, HRDATA, $time);

  COVER_VALID_READ_OK: cover property (p_valid_read_ok_response);


  // ==========================================================================
  // CA-7: HREADYOUT encoding matches error FSM
  //       Spec §5.1.3 Table 5-2:
  //         ST_OKAY → HREADYOUT=1, HRESP=0
  //         ST_ERR1 → HREADYOUT=0, HRESP=1  (first error cycle)
  //         ST_ERR2 → HREADYOUT=1, HRESP=1  (second error cycle)
  //       Validates the combinational output decode is correctly wired.
  // ==========================================================================
  property p_hreadyout_okay;
    @(posedge HCLK) disable iff (!HRESETn)
    (r_state === ST_OKAY) |-> (HREADYOUT === 1'b1 && HRESP === 1'b0);
  endproperty

  property p_hreadyout_err1;
    @(posedge HCLK) disable iff (!HRESETn)
    (r_state === ST_ERR1) |-> (HREADYOUT === 1'b0 && HRESP === 1'b1);
  endproperty

  property p_hreadyout_err2;
    @(posedge HCLK) disable iff (!HRESETn)
    (r_state === ST_ERR2) |-> (HREADYOUT === 1'b1 && HRESP === 1'b1);
  endproperty

  ASSERT_HREADYOUT_OKAY: assert property (p_hreadyout_okay)
    else $error("[CA-7a] ST_OKAY output wrong: HREADYOUT=%0b HRESP=%0b at %0t",
                HREADYOUT, HRESP, $time);

  ASSERT_HREADYOUT_ERR1: assert property (p_hreadyout_err1)
    else $error("[CA-7b] ST_ERR1 output wrong: HREADYOUT=%0b HRESP=%0b at %0t",
                HREADYOUT, HRESP, $time);

  ASSERT_HREADYOUT_ERR2: assert property (p_hreadyout_err2)
    else $error("[CA-7c] ST_ERR2 output wrong: HREADYOUT=%0b HRESP=%0b at %0t",
                HREADYOUT, HRESP, $time);

  COVER_HREADYOUT_OKAY: cover property (p_hreadyout_okay);
  COVER_HREADYOUT_ERR1: cover property (p_hreadyout_err1);
  COVER_HREADYOUT_ERR2: cover property (p_hreadyout_err2);

  // ==========================================================================
  // CA-9: No-write guarantee during error response
  //       The RTL gates memory writes with (r_state == ST_OKAY). This
  //       assertion confirms that no write commit can happen while the FSM
  //       is in an error state, providing an independent check on the gate.
  //       Checked on access_ok + s_hwrite which is the write enable condition,
  //       combined with the state being non-OKAY.
  // ==========================================================================
  property p_no_write_during_error;
    @(posedge HCLK) disable iff (!HRESETn)
    (r_state !== ST_OKAY) |-> !(access_ok && s_hwrite);
  endproperty

  ASSERT_NO_WRITE_DURING_ERROR: assert property (p_no_write_during_error)
    else $error("[CA-9] Write committed during error state r_state=%0b at %0t",
                r_state, $time);

endmodule : ahb_mem_assertions

bind ahb_mem ahb_mem_assertions u_ahb_mem_assertions (
  .HRESETn       (HRESETn),
  .HCLK          (HCLK),
  .HSEL          (HSEL),
  .HADDR         (HADDR),
  .HWRITE        (HWRITE),
  .HTRANS        (HTRANS),
  .HSIZE         (HSIZE),
  .HBURST        (HBURST),
  .HREADY        (HREADY),
  .HWDATA        (HWDATA),
  .HRDATA        (HRDATA),
  .HREADYOUT     (HREADYOUT),
  .HRESP         (HRESP),
  // Internal signals bound directly from DUT scope
  .r_state       (r_state),
  .s_hsel        (s_hsel),
  .s_haddr       (s_haddr),
  .s_hwrite      (s_hwrite),
  .s_htrans      (s_htrans),
  .s_hsize       (s_hsize),
  .valid_transfer(valid_transfer),
  .access_ok     (access_ok),
  .access_error  (access_error)
);
