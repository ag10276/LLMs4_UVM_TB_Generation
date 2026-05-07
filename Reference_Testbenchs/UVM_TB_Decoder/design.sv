module decoder(
	input logic [2:0] a,
	output logic [7:0] d
);

	always_comb begin
		unique case(a)
		3'b111: d = 8'b1000_0000;
		3'b110: d = 8'b0100_0000;
		3'b101: d = 8'b0010_0000;
		3'b100: d = 8'b0001_0000;
		3'b011: d = 8'b0000_1000;
		3'b010: d = 8'b0000_0100;
		3'b001: d = 8'b0000_0010;
		3'b000: d = 8'b0000_0001;
		default: d = 8'b0000_0000;
		endcase
	end
endmodule

interface decoder_if;
logic [2:0] a;
logic [7:0] d;
endinterface

module decoder_sva (
  input logic [2:0] a,
  input logic [7:0] d
);


  always_comb begin
    case (a)
      3'b000: DEC_000: assert final (d == 8'b0000_0001) else
                $error("[SVA] a=000: d=%08b, expected 00000001", d);
      3'b001: DEC_001: assert final (d == 8'b0000_0010) else
                $error("[SVA] a=001: d=%08b, expected 00000010", d);
      3'b010: DEC_010: assert final (d == 8'b0000_0100) else
                $error("[SVA] a=010: d=%08b, expected 00000100", d);
      3'b011: DEC_011: assert final (d == 8'b0000_1000) else
                $error("[SVA] a=011: d=%08b, expected 00001000", d);
      3'b100: DEC_100: assert final (d == 8'b0001_0000) else
                $error("[SVA] a=100: d=%08b, expected 00010000", d);
      3'b101: DEC_101: assert final (d == 8'b0010_0000) else
                $error("[SVA] a=101: d=%08b, expected 00100000", d);
      3'b110: DEC_110: assert final (d == 8'b0100_0000) else
                $error("[SVA] a=110: d=%08b, expected 01000000", d);
      3'b111: DEC_111: assert final (d == 8'b1000_0000) else
                $error("[SVA] a=111: d=%08b, expected 10000000", d);
    endcase
  end


  always_comb begin
    ONE_HOT: assert final ($onehot(d)) else
      $error("[SVA] d=%08b is not one-hot", d);
  end

  always_comb begin
    POW2: assert final ((d != 8'b0) && ((d & (d - 1)) == 8'b0)) else
      $error("[SVA] d=%08b is not a power of 2", d);
  end

  always_comb begin
    for (int i = 0; i < 8; i++) begin
      for (int j = i+1; j < 8; j++) begin
        MUTEX: assert final (!(d[i] && d[j])) else
          $error("[SVA] bits %0d and %0d both high: d=%08b", i, j, d);
      end
    end
  end

  always_comb begin
    BIT_POS: assert final (d == (8'b1 << a)) else
      $error("[SVA] a=%0b: d=%08b, expected bit %0d high", a, d, a);
  end

  always_comb begin
    NO_X_D: assert final (!$isunknown(d)) else
      $error("[SVA] X/Z detected on d");
    NO_X_A: assert final (!$isunknown(a)) else
      $error("[SVA] X/Z detected on a");
  end

endmodule

bind decoder decoder_sva u_sva (
  .a (a),
  .d (d)
);