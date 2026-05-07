module barrel_shifter_8 (
    input  logic [7:0] x,
    input  logic [2:0] s,
    output logic [7:0] y
);

logic [7:0] a, b;

assign a = s[0] ? {1'b0, x[7:1]} : x;
assign b = s[1] ? {2'b00, a[7:2]} : a;
assign y = s[2] ? {4'b0000, b[7:4]} : b;

endmodule

interface bshifter8;
  logic [7:0] x;
  logic [2:0] s;
  logic [7:0] y;
endinterface

module barrel_shifter_8_sva (
  input logic [7:0] x,
  input logic [2:0] s,
  input logic [7:0] y
);


  always_comb begin
    SHIFT_RESULT: assert final (y == (x >> s)) else
      $error("[SVA-BSR] x=%08b s=%0d | got y=%08b | exp=%08b",
              x, s, y, (x >> s));
  end

  always_comb begin
    if (s == 3'd0)
      ZERO_SHIFT: assert final (y == x) else
        $error("[SVA] s=0: y=%08b should equal x=%08b", y, x);
  end


  always_comb begin
    if (s == 3'd7)
      MAX_SHIFT: assert final (y == {7'b0, x[7]}) else
        $error("[SVA] s=7: y=%08b should be {7'b0, x[7]=%b}", y, x[7]);
  end

  always_comb begin
    NO_X_X: assert final (!$isunknown(x)) else $error("[SVA] X/Z on x");
    NO_X_S: assert final (!$isunknown(s)) else $error("[SVA] X/Z on s");
    NO_X_Y: assert final (!$isunknown(y)) else $error("[SVA] X/Z on y");
  end

endmodule

bind barrel_shifter_8 barrel_shifter_8_sva u_bsr_sva (
  .x (x),
  .s (s),
  .y (y)
);
