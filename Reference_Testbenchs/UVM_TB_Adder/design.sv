module full_adder(
  input logic a, b, cin,
  output logic sum, cout
);
  
  always_comb begin
    {cout, sum} = a + b + cin;
  end
endmodule

module adder(
  input logic [3:0] a, b,
  input logic cin,
  output logic [3:0] sum, 
  output logic cout
);
  
  logic cin2, cin3, cin4;
  
  full_adder fa1(.a(a[0]), .b(b[0]), .cin(cin), .sum(sum[0]), .cout(cin2));
  full_adder fa2(.a(a[1]), .b(b[1]), .cin(cin2), .sum(sum[1]), .cout(cin3));
  full_adder fa3(.a(a[2]), .b(b[2]), .cin(cin3), .sum(sum[2]), .cout(cin4));
  full_adder fa4(.a(a[3]), .b(b[3]), .cin(cin4), .sum(sum[3]), .cout(cout));
  
endmodule

interface adder_if;
  logic [3:0] a;
  logic [3:0] b;
  logic cin;
  logic [3:0] sum;
  logic cout;
endinterface

module adder_sva (
  input logic [3:0] a,
  input logic [3:0] b,
  input logic       cin,
  input logic [3:0] sum,
  input logic       cout
);

  always_comb begin
    FULL_ADD: assert final ({cout, sum} == (5'(a) + 5'(b) + 5'(cin))) else
      $error("[SVA] a=%0d b=%0d cin=%0d | got cout=%b sum=%04b | exp=%05b",
              a, b, cin, cout, sum, (5'(a) + 5'(b) + 5'(cin)));
  end

  always_comb begin
    SUM_RANGE: assert final ({cout, sum} <= 5'd31) else
      $error("[SVA] result %0d exceeds max possible value 31", {cout, sum});
  end

  always_comb begin
    COUT_SET: assert final (((5'(a) + 5'(b) + 5'(cin)) > 5'd15) == (cout == 1'b1)) else
      $error("[SVA] cout=%b incorrect for a=%0d b=%0d cin=%0d", cout, a, b, cin);
  end

  always_comb begin
    NO_OVERFLOW: assert final ((sum == 4'(a + b + cin))) else
      $error("[SVA] no-overflow case: sum=%0d != a+b+cin=%0d", sum, a+b+cin);
  end

  always_comb begin
    NO_X_A:   assert final (!$isunknown(a))   else $error("[SVA] X/Z on a");
    NO_X_B:   assert final (!$isunknown(b))   else $error("[SVA] X/Z on b");
    NO_X_CIN: assert final (!$isunknown(cin)) else $error("[SVA] X/Z on cin");
    NO_X_SUM: assert final (!$isunknown(sum)) else $error("[SVA] X/Z on sum");
    NO_X_CO:  assert final (!$isunknown(cout)) else $error("[SVA] X/Z on cout");
  end

endmodule

module full_adder_sva (
  input logic a,
  input logic b,
  input logic cin,
  input logic sum,
  input logic cout
);

  always_comb begin
    FA_FUNC: assert final ({cout, sum} == (2'(a) + 2'(b) + 2'(cin))) else
      $error("[FA-SVA] a=%b b=%b cin=%b | got cout=%b sum=%b | exp=%02b",
              a, b, cin, cout, sum, (2'(a) + 2'(b) + 2'(cin)));
  end

  always_comb begin
    NO_X_A:   assert final (!$isunknown(a))    else $error("[FA-SVA] X/Z on a");
    NO_X_B:   assert final (!$isunknown(b))    else $error("[FA-SVA] X/Z on b");
    NO_X_CIN: assert final (!$isunknown(cin))  else $error("[FA-SVA] X/Z on cin");
    NO_X_SUM: assert final (!$isunknown(sum))  else $error("[FA-SVA] X/Z on sum");
    NO_X_CO:  assert final (!$isunknown(cout)) else $error("[FA-SVA] X/Z on cout");
  end

endmodule

bind adder adder_sva u_adder_sva (
  .a   (a),
  .b   (b),
  .cin (cin),
  .sum (sum),
  .cout(cout)
);

bind full_adder full_adder_sva u_fa_sva (
  .a   (a),
  .b   (b),
  .cin (cin),
  .sum (sum),
  .cout(cout)
);


