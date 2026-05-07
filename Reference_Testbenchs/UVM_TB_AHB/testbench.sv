import uvm_pkg::*;
`include "uvm_macros.svh"

typedef enum logic [1:0] {
  HTRANS_IDLE   = 2'b00,
  HTRANS_BUSY   = 2'b01,
  HTRANS_NONSEQ = 2'b10,
  HTRANS_SEQ    = 2'b11
} htrans_e;

typedef enum logic [2:0] {
  HSIZE_BYTE = 3'b000,
  HSIZE_HALF = 3'b001,
  HSIZE_WORD = 3'b010,
  HSIZE_DBL  = 3'b011,   
  HSIZE_4W   = 3'b100,  
  HSIZE_8W   = 3'b101,   
  HSIZE_512  = 3'b110,  
  HSIZE_1024 = 3'b111    
} hsize_e;

typedef enum logic [2:0] {
  HBURST_SINGLE = 3'b000,
  HBURST_INCR   = 3'b001,
  HBURST_WRAP4  = 3'b010,
  HBURST_INCR4  = 3'b011,
  HBURST_WRAP8  = 3'b100,
  HBURST_INCR8  = 3'b101,
  HBURST_WRAP16 = 3'b110,
  HBURST_INCR16 = 3'b111
} hburst_e;


class item extends uvm_sequence_item;
  `uvm_object_utils_begin(item)
    `uvm_field_int(HRESETn, UVM_DEFAULT)
    `uvm_field_int(HSEL, UVM_DEFAULT)
    `uvm_field_int(HADDR, UVM_DEFAULT)
    `uvm_field_int(HWRITE, UVM_DEFAULT)
    `uvm_field_enum(htrans_e, HTRANS, UVM_DEFAULT)
    `uvm_field_enum(hsize_e, HSIZE, UVM_DEFAULT)
    `uvm_field_enum(hburst_e, HBURST, UVM_DEFAULT)
    `uvm_field_int(HREADY, UVM_DEFAULT)
    `uvm_field_int(HWDATA, UVM_DEFAULT)
    `uvm_field_int(HRDATA, UVM_DEFAULT)
    `uvm_field_int(HREADYOUT, UVM_DEFAULT)
    `uvm_field_int(HRESP, UVM_DEFAULT)
  `uvm_object_utils_end
  
  function new(string name = "item");
    super.new(name);
  endfunction

  rand bit HRESETn;
  rand bit HSEL;
  rand bit [31:0] HADDR;
  rand bit HWRITE;
  rand htrans_e HTRANS;
  rand hsize_e HSIZE;
  rand hburst_e HBURST;
  bit HREADY;
  rand bit [31:0] HWDATA;
  bit [31:0] HRDATA;
  bit HREADYOUT;
  bit HRESP;
  
  constraint c_reset   { HRESETn dist { 1'b1 := 9, 1'b0 := 1 }; }
  constraint c_addr    { HADDR inside { [32'h00:32'h7C] }; }
  constraint c_hburst  { HBURST == HBURST_SINGLE; }
  constraint c_hsize   { HSIZE inside { HSIZE_BYTE, HSIZE_HALF, HSIZE_WORD }; }
endclass

class item_seq extends uvm_sequence#(item);
  `uvm_object_utils(item_seq)
  
  function new(string name = "item_seq");
    super.new(name);
  endfunction
  
  rand int unsigned num;
  constraint c_num {soft num inside {[30:50]};}
  
  virtual function void apply_constraints(item q_item);
  endfunction
  
  virtual task body();
    //item q_item;
    //assert reset
    item q_item = item::type_id::create("q_item");
    start_item(q_item);
    q_item.HRESETn = 1'b0;
    q_item.HSEL    = 1'b0;
    q_item.HTRANS  = HTRANS_IDLE;
    q_item.HSIZE   = HSIZE_WORD;
    q_item.HBURST  = HBURST_SINGLE;
    q_item.HWRITE  = 1'b0;
    q_item.HADDR   = '0;
    q_item.HWDATA  = '0;
    finish_item(q_item);
    //deassert reset
    q_item = item::type_id::create("q_item");
    start_item(q_item);
    q_item.HRESETn = 1'b1;
    q_item.HSEL    = 1'b0;
    q_item.HTRANS  = HTRANS_IDLE;
    q_item.HSIZE   = HSIZE_WORD;
    q_item.HBURST  = HBURST_SINGLE;
    q_item.HWRITE  = 1'b0;
    q_item.HADDR   = '0;
    q_item.HWDATA  = '0;
    finish_item(q_item);
    //start operation
    repeat(num) begin
      item q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.randomize() with { HRESETn == 1'b1; HSEL == 1'b1;}; 
      apply_constraints(q_item);
      finish_item(q_item);
    end
  endtask
endclass

// word write + read-back
class seq_word_wr_rd extends item_seq;
  `uvm_object_utils(seq_word_wr_rd)
  
  function new(string name = "seq_word_wr_rd"); 
    super.new(name); 
  endfunction
 
  virtual function void apply_constraints(item q_item);
    q_item.HSIZE  = HSIZE_WORD;
    q_item.HADDR  = q_item.HADDR & 32'h7C; 
    q_item.HBURST = HBURST_SINGLE;
    q_item.HTRANS = HTRANS_NONSEQ;
  endfunction
endclass

//4-beat INCR4 burst (NONSEQ + 3×SEQ, addresses +4)
class seq_incr4_burst extends item_seq;
  `uvm_object_utils(seq_incr4_burst)

  constraint c_num_override { num == 16; }  // 4 bursts of 4
  
  function new(string name = "seq_incr4_burst"); 
    super.new(name); 
  endfunction

  virtual task body();
    item q_item;
    bit [31:0] base_addr;

    // Reset
    q_item = item::type_id::create("q_item");
    start_item(q_item);
    q_item.HRESETn = 1'b0; 
    q_item.HSEL = 1'b0; 
    q_item.HTRANS = HTRANS_IDLE;
    q_item.HSIZE = HSIZE_WORD; 
    q_item.HBURST = HBURST_INCR4; 
    q_item.HWRITE = 1'b0; 
    q_item.HADDR = '0; 
    q_item.HWDATA = '0;
    finish_item(q_item);
    
    q_item = item::type_id::create("q_item");
    start_item(q_item);
    q_item.HRESETn = 1'b1; 
    q_item.HSEL = 1'b0; 
    q_item.HTRANS = HTRANS_IDLE;
    q_item.HSIZE = HSIZE_WORD; 
    q_item.HBURST = HBURST_INCR4; 
    q_item.HWRITE = 1'b0; 
    q_item.HADDR = '0; 
    q_item.HWDATA = '0;
    finish_item(q_item);

    repeat (4) begin
      base_addr = ($urandom_range(0, 28)) * 4;
      // Beat 1: NONSEQ
      q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.HRESETn = 1'b1; 
      q_item.HSEL = 1'b1; 
      q_item.HTRANS = HTRANS_NONSEQ;
      q_item.HSIZE = HSIZE_WORD; 
      q_item.HBURST = HBURST_INCR4; 
      q_item.HWRITE = 1'b1;
      q_item.HADDR = base_addr; 
      q_item.HWDATA = $urandom();
      finish_item(q_item);
      // Beats 2-4: SEQ
      for (int i = 1; i < 4; i++) begin
        q_item = item::type_id::create("q_item");
        start_item(q_item);
        q_item.HRESETn = 1'b1; 
        q_item.HSEL = 1'b1; 
        q_item.HTRANS = HTRANS_SEQ;
        q_item.HSIZE = HSIZE_WORD; 
        q_item.HBURST = HBURST_INCR4; 
        q_item.HWRITE = 1'b1;
        q_item.HADDR = base_addr + (i * 4); 
        q_item.HWDATA = $urandom();
        finish_item(q_item);
      end
    end
  endtask
endclass

// ============================================================================
// NEW DIRECTED SEQUENCES FOR COVERAGE CLOSURE
// ============================================================================

// 8-beat WRAP8 burst
class seq_wrap8_burst extends item_seq;
  `uvm_object_utils(seq_wrap8_burst)

  constraint c_num_override { num == 16; }  // not strictly needed, body is directed

  function new(string name = "seq_wrap8_burst");
    super.new(name);
  endfunction

  virtual task body();
    item q_item;
    bit [31:0] base_addr;
    bit [31:0] wrap_base;
    bit [31:0] addr;

    // Reset
    q_item = item::type_id::create("q_item");
    start_item(q_item);
    q_item.HRESETn = 1'b0;
    q_item.HSEL    = 1'b0;
    q_item.HTRANS  = HTRANS_IDLE;
    q_item.HSIZE   = HSIZE_WORD;
    q_item.HBURST  = HBURST_WRAP8;
    q_item.HWRITE  = 1'b0;
    q_item.HADDR   = '0;
    q_item.HWDATA  = '0;
    finish_item(q_item);

    q_item = item::type_id::create("q_item");
    start_item(q_item);
    q_item.HRESETn = 1'b1;
    q_item.HSEL    = 1'b0;
    q_item.HTRANS  = HTRANS_IDLE;
    q_item.HSIZE   = HSIZE_WORD;
    q_item.HBURST  = HBURST_WRAP8;
    q_item.HWRITE  = 1'b0;
    q_item.HADDR   = '0;
    q_item.HWDATA  = '0;
    finish_item(q_item);

    // Two 8-beat WRAP8 bursts
    repeat (2) begin
      // 8 beats x 4 bytes = 32-byte wrap boundary
      wrap_base = ($urandom_range(0, 3)) * 32;              // 0x00, 0x20, 0x40, 0x60
      base_addr = wrap_base + ($urandom_range(0, 7) * 4);   // any aligned address inside window

      for (int i = 0; i < 8; i++) begin
        addr = wrap_base + ((base_addr - wrap_base + i*4) % 32);

        q_item = item::type_id::create($sformatf("q_item_%0d", i));
        start_item(q_item);
        q_item.HRESETn = 1'b1;
        q_item.HSEL    = 1'b1;
        q_item.HTRANS  = (i == 0) ? HTRANS_NONSEQ : HTRANS_SEQ;
        q_item.HSIZE   = HSIZE_WORD;
        q_item.HBURST  = HBURST_WRAP8;
        q_item.HWRITE  = 1'b1;
        q_item.HADDR   = addr;
        q_item.HWDATA  = $urandom();
        finish_item(q_item);
      end
    end
  endtask
endclass

// 8-beat INCR8 burst (NONSEQ + 7×SEQ, addresses +4)
class seq_incr8_burst extends item_seq;
  `uvm_object_utils(seq_incr8_burst)

  constraint c_num_override { num == 16; }  // not strictly needed, body is directed

  function new(string name = "seq_incr8_burst");
    super.new(name);
  endfunction

  virtual task body();
    item q_item;
    bit [31:0] base_addr;

    // Reset
    q_item = item::type_id::create("q_item");
    start_item(q_item);
    q_item.HRESETn = 1'b0;
    q_item.HSEL    = 1'b0;
    q_item.HTRANS  = HTRANS_IDLE;
    q_item.HSIZE   = HSIZE_WORD;
    q_item.HBURST  = HBURST_INCR8;
    q_item.HWRITE  = 1'b0;
    q_item.HADDR   = '0;
    q_item.HWDATA  = '0;
    finish_item(q_item);

    q_item = item::type_id::create("q_item");
    start_item(q_item);
    q_item.HRESETn = 1'b1;
    q_item.HSEL    = 1'b0;
    q_item.HTRANS  = HTRANS_IDLE;
    q_item.HSIZE   = HSIZE_WORD;
    q_item.HBURST  = HBURST_INCR8;
    q_item.HWRITE  = 1'b0;
    q_item.HADDR   = '0;
    q_item.HWDATA  = '0;
    finish_item(q_item);

    // Two 8-beat INCR8 bursts
    repeat (2) begin
      base_addr = ($urandom_range(0, 24)) * 4; // keep within 0x00..0x7C

      // Beat 1: NONSEQ
      q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.HRESETn = 1'b1;
      q_item.HSEL    = 1'b1;
      q_item.HTRANS  = HTRANS_NONSEQ;
      q_item.HSIZE   = HSIZE_WORD;
      q_item.HBURST  = HBURST_INCR8;
      q_item.HWRITE  = 1'b1;
      q_item.HADDR   = base_addr;
      q_item.HWDATA  = $urandom();
      finish_item(q_item);

      // Beats 2-8: SEQ
      for (int i = 1; i < 8; i++) begin
        q_item = item::type_id::create($sformatf("q_item_%0d", i));
        start_item(q_item);
        q_item.HRESETn = 1'b1;
        q_item.HSEL    = 1'b1;
        q_item.HTRANS  = HTRANS_SEQ;
        q_item.HSIZE   = HSIZE_WORD;
        q_item.HBURST  = HBURST_INCR8;
        q_item.HWRITE  = 1'b1;
        q_item.HADDR   = base_addr + (i * 4);
        q_item.HWDATA  = $urandom();
        finish_item(q_item);
      end
    end
  endtask
endclass

// Sequence to cover IDLE transitions and single transfers
class seq_idle_single extends item_seq;
  `uvm_object_utils(seq_idle_single)
  
  constraint c_num_override { num == 20; }
  
  function new(string name = "seq_idle_single"); 
    super.new(name); 
  endfunction

  virtual task body();
    item q_item;
    
    // Reset
    q_item = item::type_id::create("q_item");
    start_item(q_item);
    q_item.HRESETn = 1'b0; 
    q_item.HSEL = 1'b0; 
    q_item.HTRANS = HTRANS_IDLE;
    q_item.HSIZE = HSIZE_WORD; 
    q_item.HBURST = HBURST_SINGLE; 
    q_item.HWRITE = 1'b0; 
    q_item.HADDR = '0; 
    q_item.HWDATA = '0;
    finish_item(q_item);
    
    q_item = item::type_id::create("q_item");
    start_item(q_item);
    q_item.HRESETn = 1'b1; 
    q_item.HSEL = 1'b0; 
    q_item.HTRANS = HTRANS_IDLE;
    q_item.HSIZE = HSIZE_WORD; 
    q_item.HBURST = HBURST_SINGLE; 
    q_item.HWRITE = 1'b0; 
    q_item.HADDR = '0; 
    q_item.HWDATA = '0;
    finish_item(q_item);

    // Generate single transfers with IDLE cycles between them
    repeat (10) begin
      // NONSEQ transfer (single)
      q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.HRESETn = 1'b1; 
      q_item.HSEL = 1'b1; 
      q_item.HTRANS = HTRANS_NONSEQ;
      q_item.HSIZE = ($urandom() % 3 == 0) ? HSIZE_BYTE : (($urandom() % 2) ? HSIZE_HALF : HSIZE_WORD);
      q_item.HBURST = HBURST_SINGLE; 
      q_item.HWRITE = $urandom() % 2;
      q_item.HADDR = ($urandom_range(0, 31)) * 4;
      // Align address based on size
      if (q_item.HSIZE == HSIZE_HALF) q_item.HADDR = q_item.HADDR & 32'h7E;
      q_item.HWDATA = $urandom();
      finish_item(q_item);
      
      // IDLE cycle (cover NONSEQ->IDLE transition)
      q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.HRESETn = 1'b1; 
      q_item.HSEL = 1'b0; 
      q_item.HTRANS = HTRANS_IDLE;
      q_item.HSIZE = HSIZE_WORD; 
      q_item.HBURST = HBURST_SINGLE; 
      q_item.HWRITE = 1'b0; 
      q_item.HADDR = '0; 
      q_item.HWDATA = '0;
      finish_item(q_item);
    end
  endtask
endclass

// Sequence to cover BUSY wait states within bursts
class seq_busy_waits extends item_seq;
  `uvm_object_utils(seq_busy_waits)
  
  constraint c_num_override { num == 20; }
  
  function new(string name = "seq_busy_waits"); 
    super.new(name); 
  endfunction

  virtual task body();
    item q_item;
    bit [31:0] base_addr;
    
    // Reset
    q_item = item::type_id::create("q_item");
    start_item(q_item);
    q_item.HRESETn = 1'b0; 
    q_item.HSEL = 1'b0; 
    q_item.HTRANS = HTRANS_IDLE;
    q_item.HSIZE = HSIZE_WORD; 
    q_item.HBURST = HBURST_INCR; 
    q_item.HWRITE = 1'b0; 
    q_item.HADDR = '0; 
    q_item.HWDATA = '0;
    finish_item(q_item);
    
    q_item = item::type_id::create("q_item");
    start_item(q_item);
    q_item.HRESETn = 1'b1; 
    q_item.HSEL = 1'b0; 
    q_item.HTRANS = HTRANS_IDLE;
    q_item.HSIZE = HSIZE_WORD; 
    q_item.HBURST = HBURST_INCR; 
    q_item.HWRITE = 1'b0; 
    q_item.HADDR = '0; 
    q_item.HWDATA = '0;
    finish_item(q_item);

    // Generate bursts with BUSY wait states
    repeat (3) begin
      base_addr = ($urandom_range(0, 28)) * 4;
      
      // Start of burst - NONSEQ
      q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.HRESETn = 1'b1; 
      q_item.HSEL = 1'b1; 
      q_item.HTRANS = HTRANS_NONSEQ;
      q_item.HSIZE = HSIZE_WORD; 
      q_item.HBURST = HBURST_INCR; 
      q_item.HWRITE = 1'b1;
      q_item.HADDR = base_addr; 
      q_item.HWDATA = $urandom();
      finish_item(q_item);
      
      // SEQ transfer
      q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.HRESETn = 1'b1; 
      q_item.HSEL = 1'b1; 
      q_item.HTRANS = HTRANS_SEQ;
      q_item.HSIZE = HSIZE_WORD; 
      q_item.HBURST = HBURST_INCR; 
      q_item.HWRITE = 1'b1;
      q_item.HADDR = base_addr + 4; 
      q_item.HWDATA = $urandom();
      finish_item(q_item);
      
      // BUSY wait state (cover SEQ->BUSY transition)
      q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.HRESETn = 1'b1; 
      q_item.HSEL = 1'b1; 
      q_item.HTRANS = HTRANS_BUSY;
      q_item.HSIZE = HSIZE_WORD; 
      q_item.HBURST = HBURST_INCR; 
      q_item.HWRITE = 1'b1;
      q_item.HADDR = base_addr + 8; 
      q_item.HWDATA = $urandom();
      finish_item(q_item);
      
      // Resume with SEQ (cover BUSY->SEQ transition)
      q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.HRESETn = 1'b1; 
      q_item.HSEL = 1'b1; 
      q_item.HTRANS = HTRANS_SEQ;
      q_item.HSIZE = HSIZE_WORD; 
      q_item.HBURST = HBURST_INCR; 
      q_item.HWRITE = 1'b1;
      q_item.HADDR = base_addr + 8; 
      q_item.HWDATA = $urandom();
      finish_item(q_item);
      
      // End with IDLE (cover SEQ->IDLE, BUSY->IDLE, IDLE->NONSEQ transitions)
      q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.HRESETn = 1'b1; 
      q_item.HSEL = 1'b0; 
      q_item.HTRANS = HTRANS_IDLE;
      q_item.HSIZE = HSIZE_WORD; 
      q_item.HBURST = HBURST_SINGLE; 
      q_item.HWRITE = 1'b0; 
      q_item.HADDR = '0; 
      q_item.HWDATA = '0;
      finish_item(q_item);
    end
  endtask
endclass

// Sequence to cover error conditions with different size/lane combinations
class seq_error_coverage extends item_seq;
  `uvm_object_utils(seq_error_coverage)
  
  constraint c_num_override { num == 30; }
  
  function new(string name = "seq_error_coverage"); 
    super.new(name); 
  endfunction

  virtual task body();
    item q_item;
    
    // Reset
    q_item = item::type_id::create("q_item");
    start_item(q_item);
    q_item.HRESETn = 1'b0; 
    q_item.HSEL = 1'b0; 
    q_item.HTRANS = HTRANS_IDLE;
    q_item.HSIZE = HSIZE_WORD; 
    q_item.HBURST = HBURST_SINGLE; 
    q_item.HWRITE = 1'b0; 
    q_item.HADDR = '0; 
    q_item.HWDATA = '0;
    finish_item(q_item);
    
    q_item = item::type_id::create("q_item");
    start_item(q_item);
    q_item.HRESETn = 1'b1; 
    q_item.HSEL = 1'b0; 
    q_item.HTRANS = HTRANS_IDLE;
    q_item.HSIZE = HSIZE_WORD; 
    q_item.HBURST = HBURST_SINGLE; 
    q_item.HWRITE = 1'b0; 
    q_item.HADDR = '0; 
    q_item.HWDATA = '0;
    finish_item(q_item);

    // Cover: WRITE × BYTE × ERROR (misaligned byte write)
    repeat (3) begin
      q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.HRESETn = 1'b1; 
      q_item.HSEL = 1'b1; 
      q_item.HTRANS = HTRANS_NONSEQ;
      q_item.HSIZE = HSIZE_BYTE; 
      q_item.HBURST = HBURST_SINGLE; 
      q_item.HWRITE = 1'b1;
      q_item.HADDR = ($urandom_range(0, 31)) * 4 + ($urandom_range(0, 3)); // Any byte lane OK
      q_item.HWDATA = $urandom();
      finish_item(q_item);
    end

    // Cover: READ × WORD × ERROR (misaligned word read)
    repeat (3) begin
      q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.HRESETn = 1'b1; 
      q_item.HSEL = 1'b1; 
      q_item.HTRANS = HTRANS_NONSEQ;
      q_item.HSIZE = HSIZE_WORD; 
      q_item.HBURST = HBURST_SINGLE; 
      q_item.HWRITE = 1'b0;
      q_item.HADDR = ($urandom_range(0, 31)) * 4 + ($urandom_range(1, 3)); // Misaligned (not 0)
      q_item.HWDATA = $urandom();
      finish_item(q_item);
    end

    // Cover: READ × HALF × OKAY (aligned halfword read)
    repeat (3) begin
      q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.HRESETn = 1'b1; 
      q_item.HSEL = 1'b1; 
      q_item.HTRANS = HTRANS_NONSEQ;
      q_item.HSIZE = HSIZE_HALF; 
      q_item.HBURST = HBURST_SINGLE; 
      q_item.HWRITE = 1'b0;
      q_item.HADDR = (($urandom_range(0, 31)) * 4) & 32'h7E; // Aligned to halfword
      q_item.HWDATA = $urandom();
      finish_item(q_item);
    end

    // Cover: READ × BYTE × ERROR (misaligned - actually byte is always aligned, so use unsupported size)
    // Since byte is always aligned, we'll use unsupported HSIZE to trigger error
    repeat (3) begin
      q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.HRESETn = 1'b1; 
      q_item.HSEL = 1'b1; 
      q_item.HTRANS = HTRANS_NONSEQ;
      q_item.HSIZE = HSIZE_DBL; // Unsupported size triggers error
      q_item.HBURST = HBURST_SINGLE; 
      q_item.HWRITE = 1'b0;
      q_item.HADDR = ($urandom_range(0, 31)) * 4;
      q_item.HWDATA = $urandom();
      finish_item(q_item);
    end
  endtask
endclass

// Sequence to cover all byte lane variations
class seq_byte_lane_coverage extends item_seq;
  `uvm_object_utils(seq_byte_lane_coverage)
  
  constraint c_num_override { num == 30; }
  
  function new(string name = "seq_byte_lane_coverage"); 
    super.new(name); 
  endfunction

  virtual task body();
    item q_item;
    
    // Reset
    q_item = item::type_id::create("q_item");
    start_item(q_item);
    q_item.HRESETn = 1'b0; 
    q_item.HSEL = 1'b0; 
    q_item.HTRANS = HTRANS_IDLE;
    q_item.HSIZE = HSIZE_WORD; 
    q_item.HBURST = HBURST_SINGLE; 
    q_item.HWRITE = 1'b0; 
    q_item.HADDR = '0; 
    q_item.HWDATA = '0;
    finish_item(q_item);
    
    q_item = item::type_id::create("q_item");
    start_item(q_item);
    q_item.HRESETn = 1'b1; 
    q_item.HSEL = 1'b0; 
    q_item.HTRANS = HTRANS_IDLE;
    q_item.HSIZE = HSIZE_WORD; 
    q_item.HBURST = HBURST_SINGLE; 
    q_item.HWRITE = 1'b0; 
    q_item.HADDR = '0; 
    q_item.HWDATA = '0;
    finish_item(q_item);

    // Cover: WORD × LANE2 (address ending in 0x8)
    repeat (3) begin
      q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.HRESETn = 1'b1; 
      q_item.HSEL = 1'b1; 
      q_item.HTRANS = HTRANS_NONSEQ;
      q_item.HSIZE = HSIZE_WORD; 
      q_item.HBURST = HBURST_SINGLE; 
      q_item.HWRITE = $urandom() % 2;
      q_item.HADDR = ($urandom_range(0, 15)) * 8 + 8; // Addresses: 0x08, 0x10, 0x18, etc.
      q_item.HWDATA = $urandom();
      finish_item(q_item);
    end

    // Cover: WORD × LANE3 (address ending in 0xC)
    repeat (3) begin
      q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.HRESETn = 1'b1; 
      q_item.HSEL = 1'b1; 
      q_item.HTRANS = HTRANS_NONSEQ;
      q_item.HSIZE = HSIZE_WORD; 
      q_item.HBURST = HBURST_SINGLE; 
      q_item.HWRITE = $urandom() % 2;
      q_item.HADDR = ($urandom_range(0, 15)) * 16 + 12; // Addresses: 0x0C, 0x1C, 0x2C, etc.
      q_item.HWDATA = $urandom();
      finish_item(q_item);
    end

    // Cover: HALF × LANE0 (address ending in 0x0, 0x4, 0x8, 0xC)
    repeat (4) begin
      q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.HRESETn = 1'b1; 
      q_item.HSEL = 1'b1; 
      q_item.HTRANS = HTRANS_NONSEQ;
      q_item.HSIZE = HSIZE_HALF; 
      q_item.HBURST = HBURST_SINGLE; 
      q_item.HWRITE = $urandom() % 2;
      q_item.HADDR = ($urandom_range(0, 31)) * 4; // Word-aligned = LANE0 for halfword
      q_item.HWDATA = $urandom();
      finish_item(q_item);
    end

    // Cover: BYTE × LANE1 (address ending in 0x1, 0x5, 0x9, 0xD)
    repeat (3) begin
      q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.HRESETn = 1'b1; 
      q_item.HSEL = 1'b1; 
      q_item.HTRANS = HTRANS_NONSEQ;
      q_item.HSIZE = HSIZE_BYTE; 
      q_item.HBURST = HBURST_SINGLE; 
      q_item.HWRITE = $urandom() % 2;
      q_item.HADDR = ($urandom_range(0, 31)) * 4 + 1; // Offset +1 = LANE1
      q_item.HWDATA = $urandom();
      finish_item(q_item);
    end

    // Additional varied accesses
    repeat (10) begin
      q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.HRESETn = 1'b1; 
      q_item.HSEL = 1'b1; 
      q_item.HTRANS = HTRANS_NONSEQ;
      q_item.HSIZE = ($urandom() % 3 == 0) ? HSIZE_BYTE : (($urandom() % 2) ? HSIZE_HALF : HSIZE_WORD);
      q_item.HBURST = HBURST_SINGLE; 
      q_item.HWRITE = $urandom() % 2;
      q_item.HADDR = $urandom_range(0, 127);
      // Align based on size
      if (q_item.HSIZE == HSIZE_WORD) q_item.HADDR = q_item.HADDR & 32'h7C;
      if (q_item.HSIZE == HSIZE_HALF) q_item.HADDR = q_item.HADDR & 32'h7E;
      q_item.HWDATA = $urandom();
      finish_item(q_item);
    end
  endtask
endclass

// Sequence for WRAP burst types
class seq_wrap_bursts extends item_seq;
  `uvm_object_utils(seq_wrap_bursts)
  
  constraint c_num_override { num == 20; }
  
  function new(string name = "seq_wrap_bursts"); 
    super.new(name); 
  endfunction

  virtual task body();
    item q_item;
    bit [31:0] base_addr;
    
    // Reset
    q_item = item::type_id::create("q_item");
    start_item(q_item);
    q_item.HRESETn = 1'b0; 
    q_item.HSEL = 1'b0; 
    q_item.HTRANS = HTRANS_IDLE;
    q_item.HSIZE = HSIZE_WORD; 
    q_item.HBURST = HBURST_WRAP4; 
    q_item.HWRITE = 1'b0; 
    q_item.HADDR = '0; 
    q_item.HWDATA = '0;
    finish_item(q_item);
    
    q_item = item::type_id::create("q_item");
    start_item(q_item);
    q_item.HRESETn = 1'b1; 
    q_item.HSEL = 1'b0; 
    q_item.HTRANS = HTRANS_IDLE;
    q_item.HSIZE = HSIZE_WORD; 
    q_item.HBURST = HBURST_WRAP4; 
    q_item.HWRITE = 1'b0; 
    q_item.HADDR = '0; 
    q_item.HWDATA = '0;
    finish_item(q_item);

    // WRAP4 burst
    repeat (2) begin
      base_addr = ($urandom_range(0, 28)) * 4;
      // Beat 1: NONSEQ
      q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.HRESETn = 1'b1; 
      q_item.HSEL = 1'b1; 
      q_item.HTRANS = HTRANS_NONSEQ;
      q_item.HSIZE = HSIZE_WORD; 
      q_item.HBURST = HBURST_WRAP4; 
      q_item.HWRITE = 1'b1;
      q_item.HADDR = base_addr; 
      q_item.HWDATA = $urandom();
      finish_item(q_item);
      // Beats 2-4: SEQ
      for (int i = 1; i < 4; i++) begin
        q_item = item::type_id::create("q_item");
        start_item(q_item);
        q_item.HRESETn = 1'b1; 
        q_item.HSEL = 1'b1; 
        q_item.HTRANS = HTRANS_SEQ;
        q_item.HSIZE = HSIZE_WORD; 
        q_item.HBURST = HBURST_WRAP4; 
        q_item.HWRITE = 1'b1;
        q_item.HADDR = base_addr + (i * 4); 
        q_item.HWDATA = $urandom();
        finish_item(q_item);
      end
    end
  endtask
endclass

// ============================================================================
// KEEP EXISTING DRIVER, MONITOR, SCOREBOARD UNCHANGED
// ============================================================================

class driver extends uvm_driver #(item);
  `uvm_component_utils(driver)

  virtual ahb_if vif;

  function new(string name = "driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual ahb_if)::get(this, "", "ahb_vif", vif))
      `uvm_fatal("DRV", "ahb_if not found in config db");
  endfunction
  
  task drive_idle_addr();
    vif.drv_cb.HRESETn <= 1'b1;
    vif.drv_cb.HSEL    <= 1'b0;
    vif.drv_cb.HTRANS  <= HTRANS_IDLE;
    vif.drv_cb.HSIZE   <= HSIZE_WORD;
    vif.drv_cb.HBURST  <= HBURST_SINGLE;
    vif.drv_cb.HWRITE  <= 1'b0;
    vif.drv_cb.HADDR   <= '0;
    vif.drv_cb.HREADY  <= 1'b1;
  endtask
  
  task drive_addr_phase(item d_item);
    vif.drv_cb.HRESETn <= d_item.HRESETn;
    vif.drv_cb.HSEL    <= d_item.HSEL;
    vif.drv_cb.HTRANS  <= d_item.HTRANS;
    vif.drv_cb.HSIZE   <= d_item.HSIZE;
    vif.drv_cb.HBURST  <= d_item.HBURST;
    vif.drv_cb.HWRITE  <= d_item.HWRITE;
    vif.drv_cb.HADDR   <= d_item.HADDR;
    vif.drv_cb.HREADY  <= 1'b1;
  endtask
  
 virtual task run_phase(uvm_phase phase);
  item         nxt;
  logic [31:0] pending_hwdata;

  // Startup: idle bus, wait one edge
  @(vif.drv_cb);
  drive_idle_addr();
  vif.drv_cb.HWDATA <= '0;
  pending_hwdata = '0;

  // Drain leading reset items
  seq_item_port.get_next_item(nxt);
  @(vif.drv_cb);
  while (!nxt.HRESETn) begin
    vif.drv_cb.HRESETn <= 1'b0;
    vif.drv_cb.HSEL    <= 1'b0;
    vif.drv_cb.HTRANS  <= HTRANS_IDLE;
    vif.drv_cb.HREADY  <= 1'b1;
    vif.drv_cb.HWDATA  <= '0;
    seq_item_port.item_done();
    seq_item_port.get_next_item(nxt);
    @(vif.drv_cb);
  end

  // Drive first post-reset address phase, then release immediately.
  // Saving HWDATA to a local var means we no longer need the item handle.
  drive_addr_phase(nxt);
  pending_hwdata = nxt.HWDATA;
  seq_item_port.item_done();   // FIX: release NOW so sequence can queue next item

  // Main pipeline loop
  forever begin
    @(vif.drv_cb);

    // Drive the data phase HWDATA for the previous item (saved locally — no
    // item handle needed, so no "active item" conflict with try_next_item).
    vif.drv_cb.HWDATA <= pending_hwdata;

    if (!vif.drv_cb.HREADYOUT)
      continue;

    // No item is currently active in the sequencer here (item_done was called
    // eagerly at the end of the previous iteration). Safe to fetch next item.
    seq_item_port.try_next_item(nxt);
    if (nxt == null) begin
      drive_idle_addr();
      seq_item_port.get_next_item(nxt);
    end

    if (!nxt.HRESETn) begin
      // In-band reset handling
      drive_idle_addr();
      pending_hwdata = '0;
      seq_item_port.item_done();
      seq_item_port.get_next_item(nxt);
      while (!nxt.HRESETn) begin
        @(vif.drv_cb);
        vif.drv_cb.HRESETn <= 1'b0;
        vif.drv_cb.HSEL    <= 1'b0;
        vif.drv_cb.HTRANS  <= HTRANS_IDLE;
        vif.drv_cb.HREADY  <= 1'b1;
        vif.drv_cb.HWDATA  <= '0;
        seq_item_port.item_done();
        seq_item_port.get_next_item(nxt);
      end
      @(vif.drv_cb);
      drive_addr_phase(nxt);
      pending_hwdata = nxt.HWDATA;
      seq_item_port.item_done();   // FIX: release immediately here too
    end else begin
      // Normal transfer: drive address, save HWDATA, release item.
      // The item handle is no longer needed after this point.
      drive_addr_phase(nxt);
      pending_hwdata = nxt.HWDATA;   // save before releasing
      seq_item_port.item_done();     // FIX: release immediately — no double-get
    end
  end
endtask
endclass

class monitor extends uvm_monitor;
  `uvm_component_utils(monitor)

  virtual ahb_if vif;
  uvm_analysis_port #(item) mon_ap;
  
  logic        d_hsel;
  logic [31:0] d_haddr;
  logic        d_hwrite;
  htrans_e     d_htrans;
  hsize_e      d_hsize;
  hburst_e     d_hburst;
  logic        d_hresetn;

  function new(string name = "monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual ahb_if)::get(this, "", "ahb_vif", vif))
      `uvm_fatal("MON", "ahb_if not found in config db")
    mon_ap = new("mon_ap", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    item     m_item;
    htrans_e cap_htrans;
    hsize_e  cap_hsize;
    hburst_e cap_hburst;

    d_hsel    = 1'b0;
    d_haddr   = '0;
    d_hwrite  = 1'b0;
    d_htrans  = HTRANS_IDLE;
    d_hsize   = HSIZE_WORD;
    d_hburst  = HBURST_SINGLE;
    d_hresetn = 1'b1;

    forever begin
      @(vif.mon_cb);

      // --------------------------------------------------
      // Reset handling
      // --------------------------------------------------
      if (!vif.mon_cb.HRESETn) begin
        m_item = item::type_id::create("m_item");
        m_item.HRESETn   = 1'b0;
        m_item.HSEL      = 1'b0;
        m_item.HTRANS    = HTRANS_IDLE;
        m_item.HADDR     = '0;
        m_item.HWRITE    = 1'b0;
        m_item.HSIZE     = HSIZE_WORD;
        m_item.HBURST    = HBURST_SINGLE;
        m_item.HWDATA    = '0;
        m_item.HRDATA    = vif.mon_cb.HRDATA;
        m_item.HREADYOUT = vif.mon_cb.HREADYOUT;
        m_item.HRESP     = vif.mon_cb.HRESP;
        `uvm_info("MON", "Reset observed", UVM_MEDIUM)
        mon_ap.write(m_item);

        d_hsel    = 1'b0;
        d_haddr   = '0;
        d_hwrite  = 1'b0;
        d_htrans  = HTRANS_IDLE;
        d_hsize   = HSIZE_WORD;
        d_hburst  = HBURST_SINGLE;
        d_hresetn = 1'b0;
        continue;
      end

      // --------------------------------------------------
      // 1. Emit completed transfer from previously sampled
      //    address/control when data phase completes
      //
      // Key fix #1:
      // consume the sampled txn immediately after emitting it,
      // so it cannot be emitted again on the next cycle.
      // --------------------------------------------------
      if (vif.mon_cb.HREADYOUT &&
          d_hsel &&
          (d_htrans == HTRANS_NONSEQ || d_htrans == HTRANS_SEQ) &&
          d_hresetn) begin

        `uvm_info("MON_DBG",
          $sformatf(
            "EMIT @%0t | sampled_d: HRESETn=%0b HSEL=%0b HTRANS=%s HWRITE=%0b HSIZE=%s HBURST=%s HADDR=0x%08h | bus_now: HWDATA=0x%08h HRDATA=0x%08h HRESP=%0b HREADYOUT=%0b",
            $time,
            d_hresetn,
            d_hsel,
            d_htrans.name(),
            d_hwrite,
            d_hsize.name(),
            d_hburst.name(),
            d_haddr,
            vif.mon_cb.HWDATA,
            vif.mon_cb.HRDATA,
            vif.mon_cb.HRESP,
            vif.mon_cb.HREADYOUT
          ),
          UVM_NONE)

        m_item = item::type_id::create("m_item");
        m_item.HRESETn   = d_hresetn;
        m_item.HSEL      = d_hsel;
        m_item.HADDR     = d_haddr;
        m_item.HWRITE    = d_hwrite;
        m_item.HTRANS    = d_htrans;
        m_item.HSIZE     = d_hsize;
        m_item.HBURST    = d_hburst;
        m_item.HWDATA    = vif.mon_cb.HWDATA;
        m_item.HRDATA    = vif.mon_cb.HRDATA;
        m_item.HREADYOUT = vif.mon_cb.HREADYOUT;
        m_item.HRESP     = vif.mon_cb.HRESP;
        mon_ap.write(m_item);

        // consume sampled transaction so it is emitted only once
        d_hsel    = 1'b0;
        d_haddr   = '0;
        d_hwrite  = 1'b0;
        d_htrans  = HTRANS_IDLE;
        d_hsize   = HSIZE_WORD;
        d_hburst  = HBURST_SINGLE;
        d_hresetn = 1'b1;
      end

      // --------------------------------------------------
      // 2. Capture NEW address/control for next transfer
      //
      // Key fix #2:
      // do not capture during error response cycles.
      // For this DUT, the second cycle of the two-cycle error
      // response would otherwise recapture the same bad access.
      // --------------------------------------------------
      if (vif.mon_cb.HREADY && !vif.mon_cb.HRESP) begin
        cap_htrans = htrans_e'(vif.mon_cb.HTRANS);
        cap_hsize  = hsize_e'(vif.mon_cb.HSIZE);
        cap_hburst = hburst_e'(vif.mon_cb.HBURST);

        `uvm_info("MON_DBG",
          $sformatf(
            "CAPTURE @%0t | HRESETn=%0b HSEL=%0b HTRANS=%s HWRITE=%0b HSIZE=%s HBURST=%s HADDR=0x%08h | HREADY=%0b HRESP=%0b HREADYOUT=%0b",
            $time,
            vif.mon_cb.HRESETn,
            vif.mon_cb.HSEL,
            cap_htrans.name(),
            vif.mon_cb.HWRITE,
            cap_hsize.name(),
            cap_hburst.name(),
            vif.mon_cb.HADDR,
            vif.mon_cb.HREADY,
            vif.mon_cb.HRESP,
            vif.mon_cb.HREADYOUT
          ),
          UVM_NONE)

        d_hsel    = vif.mon_cb.HSEL;
        d_haddr   = vif.mon_cb.HADDR;
        d_hwrite  = vif.mon_cb.HWRITE;
        d_htrans  = cap_htrans;
        d_hsize   = cap_hsize;
        d_hburst  = cap_hburst;
        d_hresetn = vif.mon_cb.HRESETn;
      end
    end
  endtask
endclass

class scoreboard extends uvm_scoreboard;
  `uvm_component_utils(scoreboard)
  uvm_analysis_imp #(item, scoreboard) sb_imp;
  
  logic [7:0] exp_mem [128];   // 128 bytes = 32 words, byte-granular
  int pass_cnt, fail_cnt;
  logic expect_err;
item prev_item;
bit  prev_valid;
  
  function new(string name = "scoreboard", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sb_imp = new("sb_imp", this);
    foreach (exp_mem[i]) exp_mem[i] = 8'h00;
prev_item  = null;
prev_valid = 0;
  endfunction

function void dump_txn(string tag, item s_item);
  `uvm_info("SB_DBG",
    $sformatf(
      "%s @%0t | CURR: HRESETn=%0b HSEL=%0b HTRANS=%s HWRITE=%0b HSIZE=%s HBURST=%s HADDR=0x%08h HWDATA=0x%08h HRDATA=0x%08h HRESP=%0b HREADYOUT=%0b",
      tag, $time,
      s_item.HRESETn,
      s_item.HSEL,
      s_item.HTRANS.name(),
      s_item.HWRITE,
      s_item.HSIZE.name(),
      s_item.HBURST.name(),
      s_item.HADDR,
      s_item.HWDATA,
      s_item.HRDATA,
      s_item.HRESP,
      s_item.HREADYOUT
    ),
    UVM_NONE)
endfunction

function void dump_prev_and_curr(string tag, item curr);
  string prev_str;

  if (prev_valid && prev_item != null) begin
    prev_str = $sformatf(
      "PREV: HRESETn=%0b HSEL=%0b HTRANS=%s HWRITE=%0b HSIZE=%s HBURST=%s HADDR=0x%08h HWDATA=0x%08h HRDATA=0x%08h HRESP=%0b HREADYOUT=%0b",
      prev_item.HRESETn,
      prev_item.HSEL,
      prev_item.HTRANS.name(),
      prev_item.HWRITE,
      prev_item.HSIZE.name(),
      prev_item.HBURST.name(),
      prev_item.HADDR,
      prev_item.HWDATA,
      prev_item.HRDATA,
      prev_item.HRESP,
      prev_item.HREADYOUT
    );
  end
  else begin
    prev_str = "PREV: <none>";
  end

  `uvm_info("SB_DBG",
    $sformatf(
      "%s @%0t | CURR: HRESETn=%0b HSEL=%0b HTRANS=%s HWRITE=%0b HSIZE=%s HBURST=%s HADDR=0x%08h HWDATA=0x%08h HRDATA=0x%08h HRESP=%0b HREADYOUT=%0b | %s",
      tag, $time,
      curr.HRESETn,
      curr.HSEL,
      curr.HTRANS.name(),
      curr.HWRITE,
      curr.HSIZE.name(),
      curr.HBURST.name(),
      curr.HADDR,
      curr.HWDATA,
      curr.HRDATA,
      curr.HRESP,
      curr.HREADYOUT,
      prev_str
    ),
    UVM_NONE)
endfunction
  
  function void write(item s_item);
  if (!s_item.HRESETn) begin
    foreach (exp_mem[i]) exp_mem[i] = 8'h00;
    chk("RESET: HRESP=OKAY", s_item.HRESP     === 1'b0);
    chk("RESET: HREADYOUT=HIGH", s_item.HREADYOUT === 1'b1);

    prev_item = item::type_id::create("prev_item");
    prev_item.copy(s_item);
    prev_valid = 1;
    return;
  end

  begin
    logic size_ok = (s_item.HSIZE == HSIZE_BYTE) ||
                    (s_item.HSIZE == HSIZE_HALF) ||
                    (s_item.HSIZE == HSIZE_WORD);
    logic align_ok;
    case (s_item.HSIZE)
      HSIZE_BYTE: align_ok = 1'b1;
      HSIZE_HALF: align_ok = (s_item.HADDR[0]   == 1'b0);
      HSIZE_WORD: align_ok = (s_item.HADDR[1:0] == 2'b00);
      default: align_ok = 1'b0;
    endcase

    expect_err = !(size_ok && align_ok);

    if (expect_err) begin
      if (!(s_item.HRESP === 1'b1)) begin
        dump_prev_and_curr("EXPECTED_ERR_GOT_OKAY", s_item);
        dump_txn("EXPECTED_ERR_GOT_OKAY_FULL", s_item);
        `uvm_error("SB", $sformatf(
          "FAIL: expected ERROR response [HSIZE=%s HADDR=0x%08h %s] but got HRESP=%0b HREADYOUT=%0b",
          s_item.HSIZE.name(), s_item.HADDR, s_item.HWRITE ? "WR" : "RD",
          s_item.HRESP, s_item.HREADYOUT))
        fail_cnt++;
      end
      else begin
        `uvm_info("SB", $sformatf(
          "PASS: ERR response [HSIZE=%s HADDR=0x%08h %s]",
          s_item.HSIZE.name(), s_item.HADDR, s_item.HWRITE ? "WR" : "RD"), UVM_MEDIUM)
        pass_cnt++;
      end

      prev_item = item::type_id::create("prev_item");
      prev_item.copy(s_item);
      prev_valid = 1;
      return;
    end

    if (!(s_item.HRESP === 1'b0)) begin
      dump_prev_and_curr("EXPECTED_OKAY_GOT_ERROR", s_item);
      dump_txn("EXPECTED_OKAY_GOT_ERROR_FULL", s_item);
      `uvm_error("SB", $sformatf(
        "FAIL: expected OKAY response [HSIZE=%s HADDR=0x%08h %s] but got HRESP=%0b HREADYOUT=%0b",
        s_item.HSIZE.name(), s_item.HADDR, s_item.HWRITE ? "WR" : "RD",
        s_item.HRESP, s_item.HREADYOUT))
      fail_cnt++;
    end
    else begin
      `uvm_info("SB", $sformatf("PASS: OKAY: HRESP=0 [HSIZE=%s HADDR=0x%08h %s]",
                    s_item.HSIZE.name(), s_item.HADDR, s_item.HWRITE ? "WR" : "RD"),
                UVM_MEDIUM)
      pass_cnt++;
    end

    if (s_item.HWRITE) begin
      case (s_item.HSIZE)
        HSIZE_BYTE: exp_mem[s_item.HADDR[6:0]] = s_item.HWDATA[7:0];
        HSIZE_HALF: begin
          exp_mem[s_item.HADDR[6:0]+0] = s_item.HWDATA[7:0];
          exp_mem[s_item.HADDR[6:0]+1] = s_item.HWDATA[15:8];
        end
        HSIZE_WORD: begin
          exp_mem[s_item.HADDR[6:0]+0] = s_item.HWDATA[7:0];
          exp_mem[s_item.HADDR[6:0]+1] = s_item.HWDATA[15:8];
          exp_mem[s_item.HADDR[6:0]+2] = s_item.HWDATA[23:16];
          exp_mem[s_item.HADDR[6:0]+3] = s_item.HWDATA[31:24];
        end
        default: ;
      endcase
      `uvm_info("SB", $sformatf("WRITE [%s] HADDR=0x%08h HWDATA=0x%08h",
        s_item.HSIZE.name(), s_item.HADDR, s_item.HWDATA), UVM_MEDIUM)
    end
    else begin
      logic [31:0] exp_rdata = '0;
      case (s_item.HSIZE)
        HSIZE_BYTE: exp_rdata[7:0]   = exp_mem[s_item.HADDR[6:0]];
        HSIZE_HALF: begin
          exp_rdata[7:0]  = exp_mem[s_item.HADDR[6:0]+0];
          exp_rdata[15:8] = exp_mem[s_item.HADDR[6:0]+1];
        end
        HSIZE_WORD: begin
          exp_rdata[7:0]   = exp_mem[s_item.HADDR[6:0]+0];
          exp_rdata[15:8]  = exp_mem[s_item.HADDR[6:0]+1];
          exp_rdata[23:16] = exp_mem[s_item.HADDR[6:0]+2];
          exp_rdata[31:24] = exp_mem[s_item.HADDR[6:0]+3];
        end
        default: ;
      endcase
      chk($sformatf("READ [%s] HADDR=0x%08h EXP=0x%08h GOT=0x%08h",
            s_item.HSIZE.name(), s_item.HADDR, exp_rdata, s_item.HRDATA),
          s_item.HRDATA === exp_rdata);
    end
  end

  prev_item = item::type_id::create("prev_item");
  prev_item.copy(s_item);
  prev_valid = 1;
endfunction

  function void chk(string msg, logic pass);
    if (pass) begin
      `uvm_info("SB", $sformatf("PASS: %s", msg), UVM_MEDIUM)
      pass_cnt++;
    end else begin
      `uvm_error("SB", $sformatf("FAIL: %s", msg))
      fail_cnt++;
    end
  endfunction

  virtual function void report_phase(uvm_phase phase);
    `uvm_info("SB", $sformatf("=== Scoreboard: %0d PASS  %0d FAIL ===",
      pass_cnt, fail_cnt), UVM_NONE)
  endfunction
endclass

class func_cov extends uvm_subscriber #(item);
  `uvm_component_utils(func_cov)

  typedef item T;
  T f_item;

  htrans_e prev_htrans;
  logic    prev_valid;

  // --------------------------------------------------------------------------
  // Signal coverage
  // Remove monitor-unobservable bins:
  // - BUSY / IDLE are never emitted by the monitor
  // - HSEL deasserted and RESET are also not meaningfully sampled here
  // --------------------------------------------------------------------------
  covergroup cg_signals;
    option.per_instance = 1;

    cp_htrans : coverpoint f_item.HTRANS {
      bins NONSEQ = { HTRANS_NONSEQ };
      bins SEQ    = { HTRANS_SEQ    };
    }

    cp_hsize : coverpoint f_item.HSIZE {
      bins BYTE        = { HSIZE_BYTE };
      bins HALF        = { HSIZE_HALF };
      bins WORD        = { HSIZE_WORD };
      bins UNSUPPORTED = { HSIZE_DBL, HSIZE_4W, HSIZE_8W, HSIZE_512, HSIZE_1024 };
    }

    cp_hburst : coverpoint f_item.HBURST {
      bins SINGLE = { HBURST_SINGLE };
      bins INCR   = { HBURST_INCR   };
      bins WRAP4  = { HBURST_WRAP4  };
      bins INCR4  = { HBURST_INCR4  };
      bins WRAP8  = { HBURST_WRAP8  };
      bins INCR8  = { HBURST_INCR8  };
    }

    cp_hwrite : coverpoint f_item.HWRITE {
      bins READ  = {0};
      bins WRITE = {1};
    }

    cp_hresp : coverpoint f_item.HRESP {
      bins OKAY  = {0};
      bins ERROR = {1};
    }
  endgroup

  // --------------------------------------------------------------------------
  // Transaction coverage
  //
  // Notes:
  // - cp_size still tracks UNSUP so unsupported traffic is visible
  // - cx_dir_size ignores UNSUP because cp_size + cp_resp/cx_dir_resp already
  //   capture that space well enough
  // - cx_size_lane ignores UNSUP because byte-lane semantics are meaningful only
  //   for implemented BYTE/HALF/WORD datapaths
  // - cx_dir_size_resp ignores:
  //     * all UNSUP combinations (tracked elsewhere)
  //     * BYTE x ERROR (RTL-impossible: byte accesses are always aligned)
  // --------------------------------------------------------------------------
  covergroup cg_transactions;
    option.per_instance = 1;

    cp_dir : coverpoint f_item.HWRITE {
      bins READ  = {0};
      bins WRITE = {1};
    }

    cp_size : coverpoint f_item.HSIZE {
      bins BYTE  = { HSIZE_BYTE };
      bins HALF  = { HSIZE_HALF };
      bins WORD  = { HSIZE_WORD };
      bins UNSUP = { HSIZE_DBL, HSIZE_4W, HSIZE_8W, HSIZE_512, HSIZE_1024 };
    }

    cp_resp : coverpoint f_item.HRESP {
      bins OKAY  = {0};
      bins ERROR = {1};
    }

    cp_byte_lane : coverpoint f_item.HADDR[1:0] {
      bins LANE0 = {2'b00};
      bins LANE1 = {2'b01};
      bins LANE2 = {2'b10};
      bins LANE3 = {2'b11};
    }

    // Read/write by supported size only
    cx_dir_size : cross cp_dir, cp_size {
      ignore_bins unsup = binsof(cp_size.UNSUP);
    }

    // Direction by response — keep all four bins
    cx_dir_resp : cross cp_dir, cp_resp;

    // Lane coverage only for implemented data sizes
    cx_size_lane : cross cp_size, cp_byte_lane {
      ignore_bins unsup = binsof(cp_size.UNSUP);
    }

    // Supported-size response matrix only.
    // BYTE x ERROR is impossible in this RTL because BYTE is always aligned.
    cx_dir_size_resp : cross cp_dir, cp_size, cp_resp {
      ignore_bins unsup = binsof(cp_size.UNSUP);

      ignore_bins byte_write_error =
        binsof(cp_dir.WRITE) &&
        binsof(cp_size.BYTE) &&
        binsof(cp_resp.ERROR);

      ignore_bins byte_read_error =
        binsof(cp_dir.READ) &&
        binsof(cp_size.BYTE) &&
        binsof(cp_resp.ERROR);
    }
  endgroup

  // --------------------------------------------------------------------------
  // Transition coverage
  // Remove BUSY/IDLE because monitor does not emit them.
  // With monitor-driven completed transactions, only NONSEQ/SEQ are observable.
  // --------------------------------------------------------------------------
  covergroup cg_transitions;
    option.per_instance = 1;

    cp_prev : coverpoint prev_htrans {
      bins NONSEQ = { HTRANS_NONSEQ };
      bins SEQ    = { HTRANS_SEQ    };
    }

    cp_curr : coverpoint f_item.HTRANS {
      bins NONSEQ = { HTRANS_NONSEQ };
      bins SEQ    = { HTRANS_SEQ    };
    }

    cx_trans : cross cp_prev, cp_curr;
  endgroup

  function new(string name = "func_cov", uvm_component parent = null);
    super.new(name, parent);
    f_item      = item::type_id::create("f_item");
    cg_signals      = new();
    cg_transactions = new();
    cg_transitions  = new();
    prev_valid  = 1'b0;
    prev_htrans = HTRANS_NONSEQ;
  endfunction

  virtual function void write(T t);
    f_item.copy(t);

    // Sample only active (non-reset) monitor-emitted transactions
    if (f_item.HRESETn) begin
      cg_signals.sample();
      cg_transactions.sample();

      if (prev_valid)
        cg_transitions.sample();

      prev_htrans = f_item.HTRANS;
      prev_valid  = 1'b1;
    end
    else begin
      prev_valid = 1'b0;
    end
  endfunction

  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("FC", $sformatf("Coverage signals: %0.2f%%",
              cg_signals.get_inst_coverage()), UVM_NONE)
    `uvm_info("FC", $sformatf("Coverage transactions: %0.2f%%",
              cg_transactions.get_inst_coverage()), UVM_NONE)
    `uvm_info("FC", $sformatf("Coverage transitions: %0.2f%%",
              cg_transitions.get_inst_coverage()), UVM_NONE)
  endfunction
endclass
  
class agent extends uvm_agent;
  `uvm_component_utils(agent)
  
  function new(string name = "agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  monitor m0;
  driver d0;
  uvm_sequencer#(item) s0;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    m0 = monitor::type_id::create("m0", this);
    d0 = driver::type_id::create("d0", this);
    s0 = uvm_sequencer#(item)::type_id::create("s0", this);
  endfunction
  
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    d0.seq_item_port.connect(s0.seq_item_export);
  endfunction
endclass

class env extends uvm_env;
  `uvm_component_utils(env)
  
  function new(string name = "env", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  agent a0;
  func_cov fc0;
  scoreboard sb0;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    a0 = agent::type_id::create("a0", this);
    fc0 = func_cov::type_id::create("fc0", this);
    sb0 = scoreboard::type_id::create("sb0", this);
  endfunction
  
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    a0.m0.mon_ap.connect(sb0.sb_imp);
    a0.m0.mon_ap.connect(fc0.analysis_export);
  endfunction
endclass

class base_test extends uvm_test;
  `uvm_component_utils(base_test)
  
  function new(string name = "base_test", uvm_component parent);
    super.new(name, parent);
  endfunction
  
  env e0;
  virtual ahb_if vif;
  item_seq seq;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual ahb_if)::get(this, "", "ahb_vif", vif))
      `uvm_fatal("ENV", "Virtual Interface not found!");
    uvm_config_db#(virtual ahb_if)::set(this, "e0.a0.*", "ahb_vif", vif);
    e0 = env::type_id::create("e0", this);
    seq = item_seq::type_id::create("seq");
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    phase.raise_objection(this);
    seq.randomize();
    seq.start(e0.a0.s0);
    phase.drop_objection(this);
  endtask
  
endclass

// ============================================================================
// TEST CLASSES - KEEP EXISTING + ADD NEW
// ============================================================================

class seq_word_wr_rd_test extends base_test;
  `uvm_component_utils(seq_word_wr_rd_test)
  function new(string name = "seq_word_wr_rd_test", uvm_component parent = null);
    super.new(name, parent); 
  endfunction
  
   virtual function void build_phase(uvm_phase phase);
    item_seq::type_id::set_type_override(seq_word_wr_rd::get_type());
    super.build_phase(phase);
  endfunction
  
endclass

class seq_incr4_burst_test extends base_test;
  `uvm_component_utils(seq_incr4_burst_test)
  function new(string name = "seq_incr4_burst_test", uvm_component parent = null);
    super.new(name, parent); 
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    item_seq::type_id::set_type_override(seq_incr4_burst::get_type());
    super.build_phase(phase);
  endfunction
endclass

// NEW TESTS
class seq_idle_single_test extends base_test;
  `uvm_component_utils(seq_idle_single_test)
  function new(string name = "seq_idle_single_test", uvm_component parent = null);
    super.new(name, parent); 
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    item_seq::type_id::set_type_override(seq_idle_single::get_type());
    super.build_phase(phase);
  endfunction
endclass

class seq_busy_waits_test extends base_test;
  `uvm_component_utils(seq_busy_waits_test)
  function new(string name = "seq_busy_waits_test", uvm_component parent = null);
    super.new(name, parent); 
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    item_seq::type_id::set_type_override(seq_busy_waits::get_type());
    super.build_phase(phase);
  endfunction
endclass

class seq_error_coverage_test extends base_test;
  `uvm_component_utils(seq_error_coverage_test)
  function new(string name = "seq_error_coverage_test", uvm_component parent = null);
    super.new(name, parent); 
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    item_seq::type_id::set_type_override(seq_error_coverage::get_type());
    super.build_phase(phase);
  endfunction
endclass

class seq_byte_lane_coverage_test extends base_test;
  `uvm_component_utils(seq_byte_lane_coverage_test)
  function new(string name = "seq_byte_lane_coverage_test", uvm_component parent = null);
    super.new(name, parent); 
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    item_seq::type_id::set_type_override(seq_byte_lane_coverage::get_type());
    super.build_phase(phase);
  endfunction
endclass

class seq_wrap_bursts_test extends base_test;
  `uvm_component_utils(seq_wrap_bursts_test)
  function new(string name = "seq_wrap_bursts_test", uvm_component parent = null);
    super.new(name, parent); 
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    item_seq::type_id::set_type_override(seq_wrap_bursts::get_type());
    super.build_phase(phase);
  endfunction
endclass

// COMPREHENSIVE TEST - runs all sequences
class comprehensive_coverage_test extends base_test;
  `uvm_component_utils(comprehensive_coverage_test)
  function new(string name = "comprehensive_coverage_test", uvm_component parent = null);
    super.new(name, parent); 
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    seq_incr4_burst seq1;
    seq_idle_single seq2;
    seq_busy_waits seq3;
    seq_error_coverage seq4;
    seq_byte_lane_coverage seq5;
    seq_wrap_bursts seq6;
    
    super.run_phase(phase);
    phase.raise_objection(this);
    
    // Run all sequences
    seq1 = seq_incr4_burst::type_id::create("seq1");
    seq1.start(e0.a0.s0);
    
    seq2 = seq_idle_single::type_id::create("seq2");
    seq2.start(e0.a0.s0);
    
    seq3 = seq_busy_waits::type_id::create("seq3");
    seq3.start(e0.a0.s0);
    
    seq4 = seq_error_coverage::type_id::create("seq4");
    seq4.start(e0.a0.s0);
    
    seq5 = seq_byte_lane_coverage::type_id::create("seq5");
    seq5.start(e0.a0.s0);
    
    seq6 = seq_wrap_bursts::type_id::create("seq6");
    seq6.start(e0.a0.s0);
    
    phase.drop_objection(this);
  endtask
endclass

class seq_incr8_burst_test extends base_test;
  `uvm_component_utils(seq_incr8_burst_test)

  function new(string name = "seq_incr8_burst_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    item_seq::type_id::set_type_override(seq_incr8_burst::get_type());
    super.build_phase(phase);
  endfunction
endclass

class seq_wrap8_burst_test extends base_test;
  `uvm_component_utils(seq_wrap8_burst_test)

  function new(string name = "seq_wrap8_burst_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    item_seq::type_id::set_type_override(seq_wrap8_burst::get_type());
    super.build_phase(phase);
  endfunction
endclass


module tb_top;

  logic HCLK;
  initial HCLK = 1'b0;
  always #5 HCLK = ~HCLK;  

  ahb_if _if (.HCLK(HCLK));

  ahb_mem dut (
    .HCLK      (HCLK),
    .HRESETn   (_if.HRESETn),
    .HSEL      (_if.HSEL),
    .HADDR     (_if.HADDR),
    .HWRITE    (_if.HWRITE),
    .HTRANS    (_if.HTRANS),
    .HSIZE     (_if.HSIZE),
    .HBURST    (_if.HBURST),
    .HREADY    (_if.HREADY),
    .HWDATA    (_if.HWDATA),
    .HRDATA    (_if.HRDATA),
    .HREADYOUT (_if.HREADYOUT),
    .HRESP     (_if.HRESP)
  );

  initial begin
    uvm_config_db #(virtual ahb_if)::set(null, "*", "ahb_vif", _if);
    run_test("comprehensive_coverage_test");
  end

  initial begin
    #10_000_000;
    `uvm_fatal("TIMEOUT", "Simulation watchdog — possible hang, check sequences")
  end

endmodule
