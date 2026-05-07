module traffic_light_controller (
    input logic clk, reset,
    output logic [1:0] light_NS, light_EW 
);

  typedef enum logic [2:0] {S0 = 0, S1 = 1, S2 = 2, S3 = 3, SR = 4} state_e;


state_e state, next;


always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
		state <= SR;
    end else begin
      state <= next;
    end
  end


always_comb begin
    case (state)
      S0: begin
        light_NS = 2'b10;
        light_EW = 2'b00;
        next = S1;
      end
      S1: begin
        light_NS = 2'b01;
        light_EW = 2'b00;
        next = S2;
      end
      S2: begin
        light_NS = 2'b00;
        light_EW = 2'b10;
        next = S3;
      end
      S3: begin
        light_NS = 2'b00;
        light_EW = 2'b01;
        next = S0;
      end
      SR: begin
        light_NS = 2'b00;
    	light_EW = 2'b00;
    	next = S0;
      end
      default: begin
        light_NS = 2'b00;
    	light_EW = 2'b00;
    	next = S0;
      end
    endcase
  end

endmodule

interface fsm_if(input logic clk);
  logic reset;
  logic [1:0] light_NS; 
  logic [1:0] light_EW;
  
  clocking cb @(posedge clk);
    default input #1step output #0; 
    output reset;
    input light_NS, light_EW;
  endclocking
endinterface

module traffic_light_assertions (
  input logic        clk,
  input logic        reset,
  input logic [1:0]  light_NS,
  input logic [1:0]  light_EW
);

  localparam logic [1:0] RED    = 2'b00;
  localparam logic [1:0] YELLOW = 2'b01;
  localparam logic [1:0] GREEN  = 2'b10;

  // CA-1: Reset output – one cycle after reset, both lights must be red
  property p_reset_outputs;
    @(posedge clk) reset |-> (light_NS === RED && light_EW === RED);
  endproperty

  ASSERT_RESET_OUTPUTS: assert property (p_reset_outputs)
    else $error("Reset outputs wrong: NS=%0b EW=%0b at time %0t",
                light_NS, light_EW, $time);

  COVER_RESET_OUTPUTS: cover property (p_reset_outputs);

  // Mutual exclusion – NS and EW must never both be non-red simultaneously
  //       This is the most safety-critical property of any traffic light system
  property p_mutual_exclusion;
    @(posedge clk) disable iff (reset)
    not (light_NS !== RED && light_EW !== RED);
  endproperty

  ASSERT_MUTUAL_EXCLUSION: assert property (p_mutual_exclusion)
    else $error("SAFETY VIOLATION: NS=%0b EW=%0b both non-red at time %0t",
                light_NS, light_EW, $time);

  COVER_MUTUAL_EXCLUSION: cover property (p_mutual_exclusion);

  // S0 output check and transition to S1
  //       When NS=green and EW=red, next cycle must be NS=yellow and EW=red

  property p_s0_to_s1;
    @(posedge clk) disable iff (reset)
    (light_NS === GREEN && light_EW === RED)
    |=> (light_NS === YELLOW && light_EW === RED);
  endproperty

  ASSERT_S0_TO_S1: assert property (p_s0_to_s1)
    else $error("S0→S1 failed: NS=%0b EW=%0b at time %0t",
                light_NS, light_EW, $time);

  COVER_S0_TO_S1: cover property (p_s0_to_s1);

  // S1 output check and transition to S2
  //       When NS=yellow and EW=red, next cycle must be NS=red and EW=green
  property p_s1_to_s2;
    @(posedge clk) disable iff (reset)
    (light_NS === YELLOW && light_EW === RED)
    |=> (light_NS === RED && light_EW === GREEN);
  endproperty

  ASSERT_S1_TO_S2: assert property (p_s1_to_s2)
    else $error("S1→S2 failed: NS=%0b EW=%0b at time %0t",
                light_NS, light_EW, $time);

  COVER_S1_TO_S2: cover property (p_s1_to_s2);


  // S2 output check and transition to S3
  //       When NS=red and EW=green, next cycle must be NS=red and EW=yellow
  property p_s2_to_s3;
    @(posedge clk) disable iff (reset)
    (light_NS === RED && light_EW === GREEN)
    |=> (light_NS === RED && light_EW === YELLOW);
  endproperty

  ASSERT_S2_TO_S3: assert property (p_s2_to_s3)
    else $error("S2→S3 failed: NS=%0b EW=%0b at time %0t",
                light_NS, light_EW, $time);

  COVER_S2_TO_S3: cover property (p_s2_to_s3);


  // S3 output check and transition back to S0
  //       When NS=red and EW=yellow, next cycle must be NS=green and EW=red
  property p_s3_to_s0;
    @(posedge clk) disable iff (reset)
    (light_NS === RED && light_EW === YELLOW)
    |=> (light_NS === GREEN && light_EW === RED);
  endproperty

  ASSERT_S3_TO_S0: assert property (p_s3_to_s0)
    else $error("S3→S0 failed: NS=%0b EW=%0b at time %0t",
                light_NS, light_EW, $time);

  COVER_S3_TO_S0: cover property (p_s3_to_s0);


  // Valid light encoding – no undefined output combinations ever appear
  //       Legal per-direction values are only 00, 01, or 10 (11 is illegal)
  property p_valid_encoding;
    @(posedge clk)
    (light_NS !== 2'b11) && (light_EW !== 2'b11);
  endproperty

  ASSERT_VALID_ENCODING: assert property (p_valid_encoding)
    else $error("Invalid light encoding: NS=%0b EW=%0b at time %0t",
                light_NS, light_EW, $time);

endmodule : traffic_light_assertions


bind traffic_light_controller traffic_light_assertions u_traffic_light_assertions (
  .clk      (clk),
  .reset    (reset),
  .light_NS (light_NS),
  .light_EW (light_EW)
);
    
