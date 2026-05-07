module apb_memory(
  input  logic PCLK,
  input  logic PRESETn,
  input  logic [31:0]  PADDR,
  input  logic [31:0] PWDATA,
  input  logic PSEL,
  input  logic PENABLE,
  input  logic PWRITE,
  output logic [31:0] PRDATA,
  output logic PREADY,
  output logic PSLVERR
);
  logic [31:0] mem [31:0];
  typedef enum logic [1:0] {IDLE, SETUP, ACCESS} state_t;
  state_t state, next_state;

  always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) state <= IDLE;
    else state <= next_state;
  end

  always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      for (int i = 0; i < 32; i++)
        mem[i] <= '0;
    end else if (state == ACCESS && PSEL && PENABLE && PWRITE && !PADDR[5]) begin
      mem[PADDR[4:0]] <= PWDATA;
    end
  end

  always_comb begin
    next_state = state;
    PREADY     = 1'b0;
    PRDATA     = '0;
    PSLVERR    = 1'b0;

    case (state)
      IDLE: begin
        if (PSEL) next_state = SETUP;
        else next_state = IDLE;
      end

      SETUP: begin
        next_state = ACCESS;
      end

      ACCESS: begin
        PREADY  = 1'b1;
        PSLVERR = PADDR[5];
        if (PSEL && PENABLE && !PWRITE && !PADDR[5])
          PRDATA = mem[PADDR[4:0]];
        next_state = PSEL ? SETUP : IDLE;
      end

      default: next_state = IDLE;
    endcase
  end
endmodule

interface apb_if(input logic PCLK);
  logic PRESETn;
  logic [31:0]  PADDR;
  logic [31:0] PWDATA;
  logic PSEL;
  logic PENABLE;
  logic PWRITE;
  logic [31:0] PRDATA;
  logic PREADY;
  logic PSLVERR;
  
  clocking drv_cb @(posedge PCLK);
    default input #1step output #1step; 
    output PRESETn, PADDR, PWDATA, PSEL, PENABLE, PWRITE;
    input PRDATA, PREADY, PSLVERR;
  endclocking 
  
  clocking mon_cb @(posedge PCLK);
    default input #1step output #0; 
    input PRESETn, PADDR, PWDATA, PSEL, PENABLE, PWRITE, PRDATA, PREADY, PSLVERR;
  endclocking 
  
endinterface

// =============================================================================
// File: apb_memory_assertions.sv
// Description: Concurrent APB3 protocol + functional assertions for apb_memory
//
// Spec reference: ARM IHI 0024E (AMBA APB Protocol Specification)
//
// RTL state encoding:
//   IDLE   = 2'b00  → PSEL=0, PENABLE=0, PREADY=0
//   SETUP  = 2'b01  → PSEL=1, PENABLE=0, PREADY=0
//   ACCESS = 2'b10  → PSEL=1, PENABLE=1, PREADY=1
//
// Error condition: PADDR[5]=1 → out-of-range → PSLVERR=1, no write committed
// Valid range:     PADDR[4:0] → indices 0..31 of mem[]
// =============================================================================

module apb_memory_assertions (
  input logic        PCLK,
  input logic        PRESETn,
  input logic [31:0] PADDR,
  input logic [31:0] PWDATA,
  input logic        PSEL,
  input logic        PENABLE,
  input logic        PWRITE,
  input logic [31:0] PRDATA,
  input logic        PREADY,
  input logic        PSLVERR,
  // Internal state exposed via bind
  input logic [1:0]  state
);

  // --------------------------------------------------------------------------
  // Localparams for state encoding — mirrors typedef in RTL
  // --------------------------------------------------------------------------
  localparam logic [1:0] IDLE   = 2'b00;
  localparam logic [1:0] SETUP  = 2'b01;
  localparam logic [1:0] ACCESS = 2'b10;

  // ==========================================================================
  // CA-1: Reset – on active-low async reset, FSM must return to IDLE and
  //       all driven outputs must be de-asserted
  //       Uses |-> (same-cycle) because PRESETn is asynchronous;
  //       the combinational always_comb resolves PREADY/PSLVERR immediately
  // ==========================================================================
  property p_reset;
    @(posedge PCLK) !PRESETn |->
      (state === IDLE && PREADY === 1'b0 && PSLVERR === 1'b0);
  endproperty

  ASSERT_RESET: assert property (p_reset)
    else $error("[CA-1] Reset failed: state=%0b PREADY=%0b PSLVERR=%0b at %0t",
                state, PREADY, PSLVERR, $time);

  COVER_RESET: cover property (p_reset);

  // ==========================================================================
  // CA-2: IDLE → SETUP transition
  //       Spec §4.1: SETUP is entered when PSEL is asserted from IDLE.
  //       One cycle after PSEL rises in IDLE, state must be SETUP.
  // ==========================================================================

	property p_idle_to_setup;
  @(posedge PCLK) disable iff (!PRESETn)
    (state == IDLE && PSEL && !PENABLE) |=> (state == SETUP);
endproperty

ASSERT_IDLE_TO_SETUP: assert property (p_idle_to_setup)
  else $error("[CA-2] IDLE->SETUP failed: state=%0b PSEL=%0b PENABLE=%0b at %0t",
              state, PSEL, PENABLE, $time);

  COVER_IDLE_TO_SETUP: cover property (p_idle_to_setup);

  // ==========================================================================
  // CA-3: SETUP → ACCESS transition
  //       Spec §4.1: "The interface only remains in the SETUP state for one
  //       clock cycle and always moves to the ACCESS state on the next
  //       rising edge of the clock."
  //       PENABLE must be HIGH in ACCESS per spec.
  // ==========================================================================
property p_setup_to_access_shape;
  @(posedge PCLK) disable iff (!PRESETn)
    (PSEL && !PENABLE) |=> (PSEL && PENABLE);
endproperty

ASSERT_SETUP_TO_ACCESS_SHAPE: assert property (p_setup_to_access_shape)
  else $error("[CA-3] SETUP->ACCESS shape failed: PSEL=%0b PENABLE=%0b PREADY=%0b state=%0b at %0t",
              PSEL, PENABLE, PREADY, state, $time);

  // ==========================================================================
  // CA-4: PREADY only asserted in ACCESS state
  //       Spec §3.1.1: PREADY is driven by the Completer during the Access
  //       phase. RTL drives PREADY=1 combinationally only when state==ACCESS.
  //       PREADY must be 0 in IDLE and SETUP.
  // ==========================================================================
  property p_pready_only_in_access;
    @(posedge PCLK) disable iff (!PRESETn)
    (state !== ACCESS) |-> (PREADY === 1'b0);
  endproperty

  ASSERT_PREADY_ONLY_IN_ACCESS: assert property (p_pready_only_in_access)
    else $error("[CA-4] PREADY high outside ACCESS: state=%0b at %0t",
                state, $time);

  // ==========================================================================
  // CA-5: ACCESS exit transitions
  //       Spec §4.1: On PREADY=1, the bus either returns to IDLE (no further
  //       transfer) or moves directly to SETUP (back-to-back transfer).
  //       This RTL always asserts PREADY in ACCESS, so the exit fires every
  //       ACCESS cycle.
  // ==========================================================================
property p_access_to_idle;
  @(posedge PCLK) disable iff (!PRESETn)
    (state == ACCESS && PREADY && !PSEL) |=> (state == IDLE);
endproperty

property p_access_to_setup;
  @(posedge PCLK) disable iff (!PRESETn)
    (state == ACCESS && PREADY && PSEL) |=> (state == SETUP);
endproperty

ASSERT_ACCESS_TO_IDLE: assert property (p_access_to_idle)
  else $error("[CA-5a] ACCESS->IDLE failed at %0t", $time);

ASSERT_ACCESS_TO_SETUP: assert property (p_access_to_setup)
  else $error("[CA-5b] ACCESS->SETUP failed at %0t", $time);

  COVER_ACCESS_TO_IDLE:  cover property (p_access_to_idle);
  COVER_ACCESS_TO_SETUP: cover property (p_access_to_setup);

  // ==========================================================================
  // CA-6: Valid write – no error response for in-range address
  //       When ACCESS fires with PWRITE=1 and PADDR[5]=0, PSLVERR must be 0.
  //       Spec §3.4: PSLVERR is only valid when PSEL, PENABLE, PREADY all HIGH.
  // ==========================================================================
  property p_valid_write_no_error;
    @(posedge PCLK) disable iff (!PRESETn)
    (state === ACCESS && PSEL && PENABLE && PWRITE && !PADDR[5])
    |-> (PSLVERR === 1'b0);
  endproperty

  ASSERT_VALID_WRITE_NO_ERROR: assert property (p_valid_write_no_error)
    else $error("[CA-6] Spurious PSLVERR on valid write: PADDR=%0h at %0t",
                PADDR, $time);

  COVER_VALID_WRITE_NO_ERROR: cover property (p_valid_write_no_error);

  // ==========================================================================
  // CA-7: Valid read – no error response and PRDATA must be driven
  //       Spec §3.3 + Appendix A: PRDATA is valid when PSEL, PENABLE,
  //       PREADY are asserted and PWRITE is deasserted.
  // ==========================================================================
  property p_valid_read_no_error;
    @(posedge PCLK) disable iff (!PRESETn)
    (state === ACCESS && PSEL && PENABLE && !PWRITE && !PADDR[5])
    |-> (PSLVERR === 1'b0);
  endproperty

  ASSERT_VALID_READ_NO_ERROR: assert property (p_valid_read_no_error)
    else $error("[CA-7] Spurious PSLVERR on valid read: PADDR=%0h at %0t",
                PADDR, $time);

  COVER_VALID_READ_NO_ERROR: cover property (p_valid_read_no_error);

  // ==========================================================================
  // CA-8: Out-of-range address error
  //       RTL sets PSLVERR = PADDR[5] in ACCESS. Per spec §3.4, PSLVERR is
  //       only considered valid when PSEL, PENABLE, PREADY are all HIGH,
  //       which is exactly the ACCESS state in this RTL.
  // ==========================================================================
  property p_addr_out_of_range_error;
    @(posedge PCLK) disable iff (!PRESETn)
    (state === ACCESS && PSEL && PENABLE && PADDR[5])
    |-> (PSLVERR === 1'b1);
  endproperty

  ASSERT_ADDR_OOR_ERROR: assert property (p_addr_out_of_range_error)
    else $error("[CA-8] Missing PSLVERR for OOR address: PADDR=%0h at %0t",
                PADDR, $time);

  COVER_ADDR_OOR_ERROR: cover property (p_addr_out_of_range_error);

  // ==========================================================================
  // CA-9: Signal stability during ACCESS wait states
  //       Spec §3.1.2 and §3.3.2: While PENABLE is HIGH and PREADY is LOW,
  //       PADDR, PWRITE, PSEL, and PENABLE must not change.
  //       This RTL always completes in one ACCESS cycle (PREADY tied to
  //       state==ACCESS), but the property is included for protocol
  //       correctness and to catch any future PREADY extension.
  // ==========================================================================
  property p_stability_during_access;
    @(posedge PCLK) disable iff (!PRESETn)
    (state === ACCESS && PSEL && PENABLE && !PREADY)
    |=> ($stable(PADDR)   &&
         $stable(PWRITE)  &&
         $stable(PSEL)    &&
         $stable(PENABLE));
  endproperty

  ASSERT_STABILITY_DURING_ACCESS: assert property (p_stability_during_access)
    else $error("[CA-9] Signal changed during ACCESS wait state at %0t", $time);

  // ==========================================================================
  // CA-10: PENABLE must not be asserted without prior PSEL in SETUP
  //        Spec §4.1: PENABLE is only asserted in ACCESS, which can only be
  //        reached from SETUP. PENABLE HIGH while state is IDLE is illegal.
  // ==========================================================================
  property p_no_penable_in_idle;
    @(posedge PCLK) disable iff (!PRESETn)
    (state === IDLE) |-> (PENABLE === 1'b0);
  endproperty

  ASSERT_NO_PENABLE_IN_IDLE: assert property (p_no_penable_in_idle)
    else $error("[CA-10] PENABLE asserted in IDLE state at %0t", $time);

endmodule : apb_memory_assertions

bind apb_memory apb_memory_assertions u_apb_memory_assertions (
  .PCLK    (PCLK),
  .PRESETn (PRESETn),
  .PADDR   (PADDR),
  .PWDATA  (PWDATA),
  .PSEL    (PSEL),
  .PENABLE (PENABLE),
  .PWRITE  (PWRITE),
  .PRDATA  (PRDATA),
  .PREADY  (PREADY),
  .PSLVERR (PSLVERR),
  // Bind directly to internal FSM state register
  .state   (state)
);
    
