module sync_fifo(
  input logic clk,
  input logic rst_n,
  input logic w_en,
  input logic r_en,
  input logic [7:0] wr_data,
  output logic [7:0] rd_data,
  output logic full,
  output logic empty
);
  
  logic [2:0] w_ptr, r_ptr;
  logic [7:0] fifo [7:0];
  logic [3:0] count;
  
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      w_ptr <= 0;
    end
    else if(w_en && !full) begin
      fifo[w_ptr] <= wr_data;
      w_ptr <= w_ptr + 1;
    end
  end
  
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      r_ptr <= 0;
      rd_data <= 0;
    end
    else if(r_en && !empty) begin
      rd_data <= fifo[r_ptr];
      r_ptr <= r_ptr + 1;
    end
  end
  
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      count <= 0;
    end
    else begin
      case ({w_en && !full, r_en && !empty})
        2'b10: count <= count + 1; // write only
        2'b01: count <= count - 1; // read only
        2'b11: count <= count;     // simultaneous
        default: count <= count;   // idle
      endcase
    end
  end
  
  assign empty = (count == 0);
  assign full  = (count == 8);
  
endmodule

interface sync_fifo_if(input logic clk);
  logic rst_n;
  logic w_en;
  logic r_en;
  logic [7:0] wr_data;
  logic [7:0] rd_data;
  logic full;
  logic empty;
  
  clocking cb @(posedge clk);
    default input #1step output #0; 
    output rst_n, w_en, r_en, wr_data;
    input rd_data, full, empty;
  endclocking 
endinterface


module sync_fifo_assertions (
  input logic        clk,
  input logic        rst_n,
  input logic        w_en,
  input logic        r_en,
  input logic [7:0]  wr_data,
  input logic [7:0]  rd_data,
  input logic        full,
  input logic        empty,
  // Internal signals accessed via bind
  input logic [3:0]  count,
  input logic [2:0]  w_ptr,
  input logic [2:0]  r_ptr
);

  wire eff_wr = w_en && !full;   // write that will actually commit
  wire eff_rd = r_en && !empty;  // read  that will actually commit

  // Reset – after rst_n deasserts, count/empty/flags must be cleared
  property p_reset_state;
    @(posedge clk) !rst_n |-> (count === 4'h0 && empty === 1'b1 && full === 1'b0);
  endproperty

  ASSERT_RESET_STATE: assert property (p_reset_state)
    else $error("[CA-1] Reset state wrong: count=%0d empty=%0b full=%0b at time %0t",
                count, empty, full, $time);

  COVER_RESET_STATE: cover property (p_reset_state);

    // Count bounds – count must always stay within [0, 8] A value of 9–15 would indicate a pointer or counter corruption
  property p_count_bounds;
    @(posedge clk) (count >= 4'd0) && (count <= 4'd8);
  endproperty

  ASSERT_COUNT_BOUNDS: assert property (p_count_bounds)
    else $error("Count out of bounds: count=%0d at time %0t", count, $time);

  // Empty flag correctness – empty must be 1 iff count is 0
  property p_empty_flag;
    @(posedge clk) (empty === (count == 4'd0));
  endproperty

  ASSERT_EMPTY_FLAG: assert property (p_empty_flag)
    else $error("Empty flag mismatch: empty=%0b count=%0d at time %0t",
                empty, count, $time);

  //Full flag correctness – full must be 1 iff count is 8
  property p_full_flag;
    @(posedge clk) (full === (count == 4'd8));
  endproperty

  ASSERT_FULL_FLAG: assert property (p_full_flag)
    else $error("Full flag mismatch: full=%0b count=%0d at time %0t",
                full, count, $time);

  // CA-5: No read when empty – r_ptr and count must not change when r_en is asserted on an empty FIFO
  property p_no_read_when_empty;
  @(posedge clk) disable iff (!rst_n)
  (r_en && empty && !w_en) |=> (count === $past(count) && r_ptr === $past(r_ptr));
endproperty

  ASSERT_NO_READ_WHEN_EMPTY: assert property (p_no_read_when_empty)
    else $error("Illegal read when empty caused state change at time %0t", $time);

  COVER_NO_READ_WHEN_EMPTY: cover property (p_no_read_when_empty);


  // No write when full – w_ptr and count must not change when w_en is asserted on a full FIFO
  property p_no_write_when_full;
    @(posedge clk) disable iff (!rst_n)
    (w_en && full) |=> (count === $past(count) && w_ptr === $past(w_ptr));
  endproperty

  ASSERT_NO_WRITE_WHEN_FULL: assert property (p_no_write_when_full)
    else $error("Illegal write when full caused state change at time %0t", $time);

  COVER_NO_WRITE_WHEN_FULL: cover property (p_no_write_when_full);

  // Write only – count increments by exactly 1 on a write with no read
  property p_write_increments_count;
    @(posedge clk) disable iff (!rst_n)
    (eff_wr && !eff_rd) |=> (count === ($past(count) + 4'd1));
  endproperty

  ASSERT_WRITE_INCREMENTS_COUNT: assert property (p_write_increments_count)
    else $error("Write did not increment count: was %0d now %0d at time %0t",
                $past(count), count, $time);

  COVER_WRITE_INCREMENTS_COUNT: cover property (p_write_increments_count);

  // Simultaneous read+write – count must remain unchanged
  property p_simultaneous_rw_count;
    @(posedge clk) disable iff (!rst_n)
    (eff_wr && eff_rd) |=> (count === $past(count));
  endproperty

  ASSERT_SIMULTANEOUS_RW: assert property (p_simultaneous_rw_count)
    else $error("Simultaneous R+W changed count: was %0d now %0d at time %0t",
                $past(count), count, $time);

  COVER_SIMULTANEOUS_RW: cover property (p_simultaneous_rw_count);

  // Read only – count decrements by exactly 1 on a read with no write
  property p_read_decrements_count;
    @(posedge clk) disable iff (!rst_n)
    (eff_rd && !eff_wr) |=> (count === ($past(count) - 4'd1));
  endproperty

  ASSERT_READ_DECREMENTS_COUNT: assert property (p_read_decrements_count)
    else $error("Read did not decrement count: was %0d now %0d at time %0t",
                $past(count), count, $time);

  COVER_READ_DECREMENTS_COUNT: cover property (p_read_decrements_count);


  // Full/empty mutex – full and empty can never both be asserted
  //        Would require count to be both 0 and 8 simultaneously
  property p_full_empty_mutex;
    @(posedge clk) not (full && empty);
  endproperty

  ASSERT_FULL_EMPTY_MUTEX: assert property (p_full_empty_mutex)
    else $error("MUTEX VIOLATION: full and empty both asserted at time %0t", $time);

endmodule : sync_fifo_assertions


bind sync_fifo sync_fifo_assertions u_sync_fifo_assertions (
  .clk     (clk),
  .rst_n   (rst_n),
  .w_en    (w_en),
  .r_en    (r_en),
  .wr_data (wr_data),
  .rd_data (rd_data),
  .full    (full),
  .empty   (empty),
  .count   (count),
  .w_ptr   (w_ptr),
  .r_ptr   (r_ptr)
);
    
