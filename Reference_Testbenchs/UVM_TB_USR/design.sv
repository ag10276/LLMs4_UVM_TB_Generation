module universal_shift_register(
  input logic clk,
  input logic clr,
  input logic [1:0] control,
  input logic [7:0] parallel_in,
  input logic serial_in_right,
  input logic serial_in_left,
  output logic serial_out_right,
  output logic serial_out_left,
  output logic [7:0] parallel_out
);
  
  
  always@(posedge clk) begin
    if(clr) begin
      parallel_out <= 0;
    end else begin
      case(control)
        2'b00: parallel_out <= parallel_out; //hold
        2'b01: parallel_out <= {serial_in_left, parallel_out[7:1]}; //right shift
        2'b10: parallel_out <= {parallel_out[6:0], serial_in_right}; //left shift
        2'b11: parallel_out <= parallel_in; //parallel
        default: begin
        end
      endcase
    end
  end
  
  assign serial_out_right = parallel_out[0];
  assign serial_out_left = parallel_out[7];
  
endmodule

interface usr_if(input logic clk);
  logic clr;
  logic [1:0] control;
  logic [7:0] parallel_in;
  logic serial_in_right;
  logic serial_in_left;
  logic serial_out_right;
  logic serial_out_left;
  logic [7:0] parallel_out;
  
  clocking cb @(posedge clk);
    default input #1step output #0; 
    output clr, control, parallel_in, serial_in_right, serial_in_left;
    input serial_out_right, serial_out_left, parallel_out;
  endclocking 
endinterface

module usr_assertions (
  input logic        clk,
  input logic        clr,
  input logic [1:0]  control,
  input logic [7:0]  parallel_in,
  input logic        serial_in_right,
  input logic        serial_in_left,
  input logic        serial_out_right,
  input logic        serial_out_left,
  input logic [7:0]  parallel_out
);
  
  logic [7:0] prev_parallel_out;

  always_ff @(posedge clk) begin
    prev_parallel_out <= parallel_out;
  end
  
  // Synchronous reset – one cycle after clr is asserted, output is zero
  
  property p_sync_reset;
    @(posedge clk) clr |=> (parallel_out === 8'h00);
  endproperty

  ASSERT_SYNC_RESET: assert property (p_sync_reset)
    else $error("Sync reset failed: parallel_out = %0h at time %0t",
                parallel_out, $time);

  COVER_SYNC_RESET: cover property (p_sync_reset);
    
    //Hold – control=00 and no clr means output is unchanged next cycle
  property p_hold;
    @(posedge clk) disable iff (clr)
    (control === 2'b00) |=> (parallel_out === $past(parallel_out));
  endproperty

  ASSERT_HOLD: assert property (p_hold)
    else $error("Hold failed: parallel_out changed unexpectedly at time %0t", $time);

  COVER_HOLD: cover property (p_hold);
    
    //Right shift – control=01 Next parallel_out == {serial_in_left, current[7:1]}
    
    property p_right_shift;
    @(posedge clk) disable iff (clr)
    (control === 2'b01) |=>
      (parallel_out === {$past(serial_in_left), $past(parallel_out[7:1])});
  endproperty

  ASSERT_RIGHT_SHIFT: assert property (p_right_shift)
    else $error("Right shift failed at time %0t. Got %0h, expected %0h",
                $time, parallel_out,
                {$past(serial_in_left), $past(parallel_out[7:1])});

  COVER_RIGHT_SHIFT: cover property (p_right_shift);
    
    // Left shift – control=10 Next parallel_out == {current[6:0], serial_in_right}

  property p_left_shift;
    @(posedge clk) disable iff (clr)
    (control === 2'b10) |=>
      (parallel_out === {$past(parallel_out[6:0]), $past(serial_in_right)});
  endproperty

  ASSERT_LEFT_SHIFT: assert property (p_left_shift)
    else $error("Left shift failed at time %0t. Got %0h, expected %0h",
                $time, parallel_out,
                {$past(parallel_out[6:0]), $past(serial_in_right)});

  COVER_LEFT_SHIFT: cover property (p_left_shift);
    
    // Parallel load – control=11 Next parallel_out == parallel_in (captured at the same edge)
  property p_parallel_load;
    @(posedge clk) disable iff (clr)
    (control === 2'b11) |=> (parallel_out === $past(parallel_in));
  endproperty

  ASSERT_PARALLEL_LOAD: assert property (p_parallel_load)
    else $error("Parallel load failed at time %0t. Got %0h, expected %0h",
                $time, parallel_out, $past(parallel_in));

  COVER_PARALLEL_LOAD: cover property (p_parallel_load);
    
    //Load then hold – data must persist across hold cycles
  property p_load_then_hold;
  logic [7:0] loaded;
  @(posedge clk) disable iff (clr)
    ((control === 2'b11, loaded = parallel_in) ##1 (control === 2'b00))
    |=> (parallel_out === loaded);
endproperty

  ASSERT_LOAD_THEN_HOLD: assert property (p_load_then_hold)
    else $error("Loaded data not held across hold cycle at time %0t", $time);

  COVER_LOAD_THEN_HOLD: cover property (p_load_then_hold);

endmodule : usr_assertions
    
    bind universal_shift_register usr_assertions u_usr_assertions (
  .clk             (clk),
  .clr             (clr),
  .control         (control),
  .parallel_in     (parallel_in),
  .serial_in_right (serial_in_right),
  .serial_in_left  (serial_in_left),
  .serial_out_right(serial_out_right),
  .serial_out_left (serial_out_left),
  .parallel_out    (parallel_out)
);
    
