module counter(
  input logic clk,
  input logic rst,
  input logic up,
  output logic [3:0] dout
);
  
  always_ff @(posedge clk) begin
    if(rst) begin
      dout <= 0;
    end
    else begin
      if(up == 1'b1) begin
        dout <= dout + 1;
      end else begin
        dout <= dout - 1;
      end
    end
  end 
endmodule

interface counter_if(input logic clk);
  logic rst;
  logic up;
  logic [3:0] dout;
  
  clocking cb_drv @(posedge clk);
    default input #1step output #1; 
    output rst, up;
    input dout;
  endclocking
  
  clocking cb_mon @(posedge clk);
    default input #1step; 
    input rst, up, dout;
  endclocking
  
  modport DRV (clocking cb_drv, input clk);
  modport MON (clocking cb_mon, input clk);       
endinterface
    
    // =============================================================================
// File: counter_assertions.sv
// Description: Concurrent assertions for a 4-bit up/down counter
//
// Behavior:
//   rst=1        → dout clears to 0 next cycle
//   rst=0, up=1  → dout increments by 1 (wraps 15→0)
//   rst=0, up=0  → dout decrements by 1 (wraps 0→15)
// =============================================================================

module counter_assertions (
  input logic        clk,
  input logic        rst,
  input logic        up,
  input logic [3:0]  dout
);

  // Synchronous reset – one cycle after rst, dout must be 0
  property p_sync_reset;
    @(posedge clk) rst |=> (dout === 4'h0);
  endproperty

  ASSERT_SYNC_RESET: assert property (p_sync_reset)
    else $error("[CA-1] Reset failed: dout = %0h (expected 0) at time %0t",
                dout, $time);

  COVER_SYNC_RESET: cover property (p_sync_reset);

  // Count up – dout increments by 1, including natural 15→0 wrap
  property p_count_up;
    @(posedge clk) disable iff (rst)
    (!rst && up) |=> (dout === ($past(dout) + 4'd1));
  endproperty

  ASSERT_COUNT_UP: assert property (p_count_up)
    else $error("Count up failed: expected %0h, got %0h at time %0t",
                ($past(dout) + 4'd1), dout, $time);

  COVER_COUNT_UP: cover property (p_count_up);

  // Count down – dout decrements by 1, including natural 0→15 wrap
  property p_count_down;
    @(posedge clk) disable iff (rst)
    (!rst && !up) |=> (dout === ($past(dout) - 4'd1));
  endproperty

  ASSERT_COUNT_DOWN: assert property (p_count_down)
    else $error("Count down failed: expected %0h, got %0h at time %0t",
                ($past(dout) - 4'd1), dout, $time);

  COVER_COUNT_DOWN: cover property (p_count_down);


  // Wrap up – natural rollover from 15 to 0 on an up-count
  property p_wrap_up;
    @(posedge clk) disable iff (rst)
    (!rst && up && (dout === 4'hF)) |=> (dout === 4'h0);
  endproperty

  ASSERT_WRAP_UP: assert property (p_wrap_up)
    else $error("Wrap up failed: expected 0, got %0h at time %0t",
                dout, $time);

  COVER_WRAP_UP: cover property (p_wrap_up);

  // Wrap down – natural rollover from 0 to 15 on a down-count
  property p_wrap_down;
    @(posedge clk) disable iff (rst)
    (!rst && !up && (dout === 4'h0)) |=> (dout === 4'hF);
  endproperty

  ASSERT_WRAP_DOWN: assert property (p_wrap_down)
    else $error("Wrap down failed: expected 15, got %0h at time %0t",
                dout, $time);

  COVER_WRAP_DOWN: cover property (p_wrap_down);


  //Reset dominance – rst overrides up/down regardless of up value
  property p_reset_dominance;
    @(posedge clk) rst |=> (dout === 4'h0);
  endproperty

  ASSERT_RESET_DOMINANCE: assert property (p_reset_dominance)
    else $error("Reset dominance failed: dout = %0h at time %0t",
                dout, $time);

  COVER_RESET_DOMINANCE: cover property (p_reset_dominance);

endmodule : counter_assertions

bind counter counter_assertions u_counter_assertions (
  .clk  (clk),
  .rst  (rst),
  .up   (up),
  .dout (dout)
);
