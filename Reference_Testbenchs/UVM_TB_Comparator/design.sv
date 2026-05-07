module comparator(
  input logic [1:0] a, 
  input logic [1:0] b,
  output logic agreaterb,
  output logic aequalb, 
  output logic alesserb
);
  
  always_comb begin
    if(a > b) begin
      agreaterb = 1'b1;
      aequalb = 1'b0;
      alesserb = 1'b0;
    end else if (a < b) begin
      agreaterb = 1'b0;
      aequalb = 1'b0;
      alesserb = 1'b1;
    end else begin
      agreaterb = 1'b0;
      aequalb = 1'b1;
      alesserb = 1'b0;
    end
  end  
endmodule

interface comp_if;
  logic [1:0] a;
  logic [1:0] b;
  logic agreaterb;
  logic aequalb;
  logic alesserb;
endinterface

module comparator_sva (
  input logic [1:0] a,
  input logic [1:0] b,
  input logic       agreaterb,
  input logic       aequalb,
  input logic       alesserb
);

  always_comb begin
    if (a > b) begin
      GT_HIGH:  assert final (agreaterb == 1'b1) else
                  $error("[SVA] a>b: agreaterb should be 1, got %b", agreaterb);
      GT_EQ:    assert final (aequalb   == 1'b0) else
                  $error("[SVA] a>b: aequalb should be 0, got %b", aequalb);
      GT_LT:    assert final (alesserb  == 1'b0) else
                  $error("[SVA] a>b: alesserb should be 0, got %b", alesserb);
    end else if (a < b) begin
      LT_HIGH:  assert final (alesserb  == 1'b1) else
                  $error("[SVA] a<b: alesserb should be 1, got %b", alesserb);
      LT_EQ:    assert final (aequalb   == 1'b0) else
                  $error("[SVA] a<b: aequalb should be 0, got %b", aequalb);
      LT_GT:    assert final (agreaterb == 1'b0) else
                  $error("[SVA] a<b: agreaterb should be 0, got %b", agreaterb);
    end else begin
      EQ_HIGH:  assert final (aequalb   == 1'b1) else
                  $error("[SVA] a==b: aequalb should be 1, got %b", aequalb);
      EQ_GT:    assert final (agreaterb == 1'b0) else
                  $error("[SVA] a==b: agreaterb should be 0, got %b", agreaterb);
      EQ_LT:    assert final (alesserb  == 1'b0) else
                  $error("[SVA] a==b: alesserb should be 0, got %b", alesserb);
    end
  end

  always_comb begin
    ONEHOT_OUT: assert final ($onehot({agreaterb, aequalb, alesserb})) else
      $error("[SVA] outputs not one-hot: agreaterb=%b aequalb=%b alesserb=%b",
              agreaterb, aequalb, alesserb);
  end

  always_comb begin
    NOT_ALL_ZERO: assert final (agreaterb | aequalb | alesserb) else
      $error("[SVA] all outputs are 0 — invalid state");
  end


  always_comb begin
    ANTI_SYM: assert final (!(agreaterb && alesserb)) else
      $error("[SVA] agreaterb and alesserb both high — impossible");
  end

  always_comb begin
    NO_X_A:         assert final (!$isunknown(a))         else $error("[SVA] X/Z on a");
    NO_X_B:         assert final (!$isunknown(b))         else $error("[SVA] X/Z on b");
    NO_X_AGREATERB: assert final (!$isunknown(agreaterb)) else $error("[SVA] X/Z on agreaterb");
    NO_X_AEQUALB:   assert final (!$isunknown(aequalb))   else $error("[SVA] X/Z on aequalb");
    NO_X_ALESSERB:  assert final (!$isunknown(alesserb))  else $error("[SVA] X/Z on alesserb");
  end

endmodule


bind comparator comparator_sva u_sva (
  .a         (a),
  .b         (b),
  .agreaterb (agreaterb),
  .aequalb   (aequalb),
  .alesserb  (alesserb)
);

