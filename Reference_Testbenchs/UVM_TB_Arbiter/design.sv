module round_robin_arbiter #(
    parameter int N = 4
) (
    input  logic clk,
    input  logic rst_n,    
    input  logic [N-1:0] req,     
    output logic [N-1:0] grant     
);
 
    logic [N-1:0] priority_ptr;   
    logic [N-1:0] mask;          
    logic [N-1:0] masked_req;    
  
    assign mask = ~(priority_ptr - 1'b1);
    assign masked_req = req & mask;
    
    // Fixed: Separate intermediate signals for clarity
    logic [N-1:0] masked_grant, raw_grant;
    assign masked_grant = masked_req & (~masked_req + 1'b1);
    assign raw_grant = req & (~req + 1'b1);
    assign grant = (|masked_req) ? masked_grant : raw_grant;
  
    // Fixed: Use grant directly - no combinational loop because
    // the grant value is sampled at clock edge, then priority_ptr
    // updates for the NEXT cycle
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            priority_ptr <= {{(N-1){1'b0}}, 1'b1};  
        else if (|grant)
            priority_ptr <= {grant[N-2:0], grant[N-1]};
        // else: hold current value (implicit)
    end
endmodule

interface arb_if #(parameter int N = 4) (input logic clk);
    logic         rst_n;
    logic [N-1:0] req;
    logic [N-1:0] grant;
  
    clocking cb_drv @(posedge clk);
        default input #1 output #1;
        output rst_n;
        output req;
        input  grant;
    endclocking
 
    clocking cb_mon @(posedge clk);
        default input #1;
        input rst_n;
        input req;
        input grant;
    endclocking
endinterface

module rr_arbiter_assertions #(parameter int N = 4) (
  input logic        clk,
  input logic        rst_n,
  input logic [N-1:0] req,
  input logic [N-1:0] grant,
  // Internal signals accessed via bind
  input logic [N-1:0] priority_ptr,
  input logic [N-1:0] mask,
  input logic [N-1:0] masked_req,
  input logic [N-1:0] next_ptr
);

  // Returns 1 if val is one-hot (exactly one bit set)
  function automatic logic is_one_hot(input logic [N-1:0] val);
    return (val != '0) && ((val & (val - 1'b1)) == '0);
  endfunction

  // Returns 1 if val is one-hot OR all-zero
  function automatic logic is_one_hot_or_zero(input logic [N-1:0] val);
    return (val == '0) || ((val & (val - 1'b1)) == '0);
  endfunction

  // Reset
  property p_reset;
    @(posedge clk)
    !rst_n |-> (priority_ptr === {{(N-1){1'b0}}, 1'b1});
  endproperty

  ASSERT_RESET: assert property (p_reset)
    else $error("Reset failed: priority_ptr=%0b (expected %0b) at %0t",
                priority_ptr, {{(N-1){1'b0}}, 1'b1}, $time);

  COVER_RESET: cover property (p_reset);

  //Grant is one-hot or all-zero
  property p_grant_one_hot_or_zero;
    @(posedge clk) disable iff (!rst_n)
    is_one_hot_or_zero(grant);
  endproperty

  ASSERT_GRANT_ONE_HOT_OR_ZERO: assert property (p_grant_one_hot_or_zero)
    else $error("grant is not one-hot or zero: grant=%0b at %0t",
                grant, $time);

  // Grant only for asserted requests
  property p_grant_subset_of_req;
    @(posedge clk) disable iff (!rst_n)
    (grant & ~req) === {N{1'b0}};
  endproperty

  ASSERT_GRANT_SUBSET_REQ: assert property (p_grant_subset_of_req)
    else $error("Grant for non-requesting port: grant=%0b req=%0b at %0t",
                grant, req, $time);

  // No grant when no requests
  property p_no_grant_when_no_req;
    @(posedge clk) disable iff (!rst_n)
    (req === {N{1'b0}}) |-> (grant === {N{1'b0}});
  endproperty

  ASSERT_NO_GRANT_NO_REQ: assert property (p_no_grant_when_no_req)
    else $error("Grant issued with req=0: grant=%0b at %0t",
                grant, $time);

  COVER_NO_GRANT_NO_REQ: cover property (p_no_grant_when_no_req);

  // priority_ptr is always one-hot
  property p_ptr_one_hot;
    @(posedge clk) disable iff (!rst_n)
    is_one_hot(priority_ptr);
  endproperty

  ASSERT_PTR_ONE_HOT: assert property (p_ptr_one_hot)
    else $error("priority_ptr is not one-hot: ptr=%0b at %0t",
                priority_ptr, $time);

  // Pointer advances (left-rotates by 1) after a grant
 property p_ptr_advances_after_grant;
  @(posedge clk) disable iff (!rst_n)
  ($past(rst_n) && $past(|grant)) |->
    (priority_ptr === {$past(grant[N-2:0]), $past(grant[N-1])});
endproperty

  ASSERT_PTR_ADVANCES: assert property (p_ptr_advances_after_grant)
    else $error("ptr did not advance after grant: ptr=%0b past_grant=%0b at %0t",
                priority_ptr, $past(grant), $time);

  COVER_PTR_ADVANCES: cover property (p_ptr_advances_after_grant);

  // Pointer holds when no grant is issued
  property p_ptr_holds_when_no_grant;
    @(posedge clk) disable iff (!rst_n)
    (!($past(|grant))) |-> (priority_ptr === $past(priority_ptr));
  endproperty

  ASSERT_PTR_HOLDS: assert property (p_ptr_holds_when_no_grant)
    else $error("ptr changed without a grant: ptr=%0b past_ptr=%0b at %0t",
                priority_ptr, $past(priority_ptr), $time);

  COVER_PTR_HOLDS: cover property (p_ptr_holds_when_no_grant);

  // Mask-first priority 
  property p_masked_priority_respected;
    @(posedge clk) disable iff (!rst_n)
    (|masked_req) |-> ((grant & masked_req) === grant && grant !== {N{1'b0}});
  endproperty

  ASSERT_MASKED_PRIORITY: assert property (p_masked_priority_respected)
    else $error("Grant bypassed mask: grant=%0b masked_req=%0b ptr=%0b at %0t",
                grant, masked_req, priority_ptr, $time);

  COVER_MASKED_PRIORITY: cover property (p_masked_priority_respected);


  //Wrap-around fallback 
  property p_wraparound_fallback;
    @(posedge clk) disable iff (!rst_n)
    (!($past(|masked_req)) && |req) |->
      (|grant && (grant & req) === grant);
  endproperty

  ASSERT_WRAPAROUND: assert property (p_wraparound_fallback)
    else $error("Wrap-around grant wrong: grant=%0b req=%0b at %0t",
                grant, req, $time);

  COVER_WRAPAROUND: cover property (p_wraparound_fallback);

  // Lowest-bit selection correctness
  property p_lowest_bit_masked;
    @(posedge clk) disable iff (!rst_n)
    (|masked_req) |->
      (grant === (masked_req & (~masked_req + 1'b1)));
  endproperty

  ASSERT_LOWEST_BIT_MASKED: assert property (p_lowest_bit_masked)
    else $error("Wrong bit selected from masked_req: grant=%0b masked_req=%0b at %0t",
                grant, masked_req, $time);

  COVER_LOWEST_BIT_MASKED: cover property (p_lowest_bit_masked);
  
property p_raw_only_when_no_masked;
  @(posedge clk) disable iff (!rst_n)
  ((masked_req == '0) && (req != '0)) |->
    (grant === (req & (~req + 1'b1)));
endproperty

ASSERT_LOWEST_BIT_RAW: assert property (p_raw_only_when_no_masked)
  else $error("Wrong bit selected from raw req: grant=%0b req=%0b at %0t",
              grant, req, $time);

COVER_LOWEST_BIT_RAW: cover property (p_raw_only_when_no_masked);	

endmodule : rr_arbiter_assertions


bind round_robin_arbiter
  rr_arbiter_assertions #(.N(N)) u_rr_arbiter_assertions (
    .clk          (clk),
    .rst_n        (rst_n),
    .req          (req),
    .grant        (grant),
    .priority_ptr (priority_ptr),
    .mask         (mask),
    .masked_req   (masked_req)
  );
