import uvm_pkg::*;
`include "uvm_macros.svh"

class item extends uvm_sequence_item;
  `uvm_object_utils(item)
  
  function new(string name = "item");
    super.new(name);
  endfunction
  
  rand bit [3:0] a, b;
  rand bit cin;
  bit [3:0] sum;
  bit cout;
endclass

class item_seq extends uvm_sequence#(item);
  `uvm_object_utils(item_seq)
  
  function new(string name = "item_seq");
    super.new(name);
  endfunction
  
  rand int num;
  constraint c_num {num inside {[500:1000]};} 
  
  virtual task body();
    repeat(num) begin
      item m_item = item::type_id::create("item");
      start_item(m_item);
      m_item.randomize();
      finish_item(m_item);
    end
  endtask
endclass

class driver extends uvm_driver#(item);
  `uvm_component_utils(driver)
  
  function new(string name = "driver", uvm_component parent);
    super.new(name, parent);
  endfunction
  
  virtual adder_if vif;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual adder_if)::get(this, "", "adder_vif", vif))
      `uvm_fatal("DRV", "Could not get vif");
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
      item d_item;
      seq_item_port.get_next_item(d_item);
      vif.a = d_item.a;
      vif.b = d_item.b;
      vif.cin = d_item.cin;
      #0;
      seq_item_port.item_done();
      #1;
    end
  endtask
endclass

class monitor extends uvm_monitor;
  `uvm_component_utils(monitor)
  
  virtual adder_if vif;
  uvm_analysis_port#(item) mon_ap;
  
  function new(string name = "monitor", uvm_component parent);
    super.new(name, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual adder_if)::get(this, "", "adder_vif", vif))
      `uvm_fatal("MON","Virtual iterface not found");
    mon_ap = new("mon_ap", this);
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
      item m_item = item::type_id::create("m_item");
      @(vif.a or vif.b or vif.cin);
      #0;
      m_item.a = vif.a;
      m_item.b = vif.b;
      m_item.cin = vif.cin;
      m_item.sum = vif.sum;
      m_item.cout = vif.cout;
      mon_ap.write(m_item);
    end
  endtask
endclass

class scoreboard extends uvm_scoreboard;
  `uvm_component_utils(scoreboard)
  
  function new(string name = "scoreboard", uvm_component parent);
    super.new(name, parent);
  endfunction
  
  uvm_analysis_imp#(item, scoreboard) sb_imp;
  
  logic [3:0] exp_sum;
  logic exp_cout;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sb_imp = new("sb_imp", this);
  endfunction
  
  function void write(item s_item);
    {exp_cout, exp_sum} = s_item.a + s_item.b + s_item.cin;
    
    if(s_item.sum == exp_sum && s_item.cout == exp_cout) begin
      `uvm_info("SB", "Sum and Cout are as expected", UVM_NONE);
    end else begin
      `uvm_error("SB", $sformatf("a: %0d, b:%0d, cin:%0d, op_sum:%0d, op_cout:%0d, exp_sum:%0d, exp+cout:%0d",s_item.a, s_item.b, s_item.cin, s_item.sum, s_item.cout, exp_sum, exp_cout));
    end
  endfunction
endclass

class fun_cov extends uvm_subscriber#(item);
  `uvm_component_utils(fun_cov)
  
  typedef item T;
  T fc_item;
  real cov;
  
  covergroup cg;
    option.per_instance = 1;
    
    cp_a: coverpoint fc_item.a {bins all[] = {[0:15]};}
    cp_b: coverpoint fc_item.b {bins all[] = {[0:15]};}
    cp_cin: coverpoint fc_item.cin {bins all[] = {[0:1]};}
    
    cp_a_b_cin: cross cp_a, cp_b, cp_cin;
  endgroup
  
  function new(string name = "fun_cov", uvm_component parent);
    super.new(name, parent);
    fc_item = item::type_id::create("fc_item");
    cg = new();
  endfunction
  
  virtual function void write (T t);
    fc_item.a = t.a;
    fc_item.b = t.b;
    fc_item.cin = t.cin;
    cg.sample();
  endfunction
  
  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    cov = cg.get_inst_coverage();
    `uvm_info(get_type_name(), $sformatf("Functional Coverage: %0.2f%%", cov), UVM_NONE)
  endfunction
endclass

class agent extends uvm_agent;
  `uvm_component_utils(agent)
  
  function new(string name = "agent", uvm_component parent);
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
  
  function new(string name="env", uvm_component parent);
    super.new(name, parent);
  endfunction
  
  agent a0;
  fun_cov fc0;
  scoreboard sb0;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    a0 = agent::type_id::create("a0", this);
    fc0 = fun_cov::type_id::create("fc0", this);
    sb0 = scoreboard::type_id::create("sb0", this);
  endfunction
  
  virtual function void connect_phase(uvm_phase phase);
    a0.m0.mon_ap.connect(sb0.sb_imp);
    a0.m0.mon_ap.connect(fc0.analysis_export);
  endfunction
endclass

class test extends uvm_test;
  `uvm_component_utils(test);
  
  function new(string name = "env", uvm_component parent);
    super.new(name, parent);
  endfunction
  
  virtual adder_if vif;
  env e0;
  item_seq seq;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    e0 = env::type_id::create("env", this);
    if(!uvm_config_db#(virtual adder_if)::get(this, "", "adder_vif", vif))
      `uvm_fatal("ENV","Virtual iterface not found");
    uvm_config_db#(virtual adder_if)::set(this, "e0.a0.*", "adder_vif", vif);
    seq = item_seq::type_id::create("seq");
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    seq.randomize();
    seq.start(e0.a0.s0);
    phase.drop_objection(this);
  endtask
endclass

// ============================================================================
// Directed Test Sequence for 4-bit Adder Coverage Closure
// ============================================================================
// Purpose: Target the 102 uncovered cross bins in cp_a_b_cin
// Usage: Add this to your testbench.sv file (after existing sequences)
// ============================================================================

class directed_item_seq extends uvm_sequence#(item);
  `uvm_object_utils(directed_item_seq)
  
  function new(string name = "directed_item_seq");
    super.new(name);
  endfunction
  
  virtual task body();
    item m_item;
    
    `uvm_info("DIRECTED_SEQ", "Starting directed coverage closure sequence", UVM_LOW)
    
    // All 102 uncovered bins extracted from grpinfo.txt
    // Format: {a, b, cin}
    
    // Bin 1-10
    send_directed(4'h0, 4'h0, 1'b1);
    send_directed(4'h0, 4'h4, 1'b1);
    send_directed(4'h0, 4'h5, 1'b0);
    send_directed(4'h0, 4'h6, 1'b1);
    send_directed(4'h0, 4'hb, 1'b1);
    send_directed(4'h0, 4'he, 1'b0);
    send_directed(4'h0, 4'hf, 1'b1);
    send_directed(4'h1, 4'h2, 1'b0);
    send_directed(4'h1, 4'h5, 1'b0);
    send_directed(4'h1, 4'ha, 1'b0);
    
    // Bin 11-20
    send_directed(4'h1, 4'hb, 1'b1);
    send_directed(4'h1, 4'hf, 1'b1);
    send_directed(4'h2, 4'h3, 1'b1);
    send_directed(4'h2, 4'h4, 1'b1);
    send_directed(4'h2, 4'ha, 1'b1);
    send_directed(4'h2, 4'hc, 1'b0);
    send_directed(4'h3, 4'h3, 1'b1);
    send_directed(4'h3, 4'h5, 1'b1);
    send_directed(4'h3, 4'ha, 1'b0);
    send_directed(4'h3, 4'hb, 1'b1);
    
    // Bin 21-30
    send_directed(4'h3, 4'he, 1'b0);
    send_directed(4'h4, 4'h0, 1'b0);
    send_directed(4'h4, 4'h0, 1'b1);
    send_directed(4'h4, 4'h3, 1'b1);
    send_directed(4'h4, 4'h5, 1'b0);
    send_directed(4'h4, 4'h7, 1'b0);
    send_directed(4'h4, 4'ha, 1'b1);
    send_directed(4'h4, 4'hb, 1'b0);
    send_directed(4'h4, 4'hc, 1'b0);
    send_directed(4'h4, 4'he, 1'b0);
    
    // Bin 31-40
    send_directed(4'h4, 4'hf, 1'b1);
    send_directed(4'h5, 4'h0, 1'b1);
    send_directed(4'h5, 4'h4, 1'b1);
    send_directed(4'h5, 4'he, 1'b0);
    send_directed(4'h6, 4'h0, 1'b0);
    send_directed(4'h6, 4'h3, 1'b0);
    send_directed(4'h6, 4'h4, 1'b1);
    send_directed(4'h6, 4'h8, 1'b1);
    send_directed(4'h7, 4'h1, 1'b0);
    send_directed(4'h7, 4'h2, 1'b1);
    
    // Bin 41-50
    send_directed(4'h7, 4'h3, 1'b1);
    send_directed(4'h7, 4'h4, 1'b0);
    send_directed(4'h7, 4'h9, 1'b0);
    send_directed(4'h7, 4'he, 1'b0);
    send_directed(4'h8, 4'h2, 1'b0);
    send_directed(4'h8, 4'h4, 1'b1);
    send_directed(4'h8, 4'h8, 1'b1);
    send_directed(4'h9, 4'h5, 1'b0);
    send_directed(4'h9, 4'h6, 1'b0);
    send_directed(4'h9, 4'h8, 1'b0);
    
    // Bin 51-60
    send_directed(4'ha, 4'h2, 1'b1);
    send_directed(4'ha, 4'h9, 1'b1);
    send_directed(4'hb, 4'h0, 1'b1);
    send_directed(4'hb, 4'h7, 1'b0);
    send_directed(4'hb, 4'hd, 1'b0);
    send_directed(4'hb, 4'he, 1'b0);
    send_directed(4'hc, 4'h0, 1'b0);
    send_directed(4'hc, 4'h1, 1'b0);
    send_directed(4'hc, 4'h3, 1'b1);
    send_directed(4'hc, 4'hc, 1'b1);
    
    // Bin 61-70
    send_directed(4'hc, 4'hf, 1'b0);
    send_directed(4'hd, 4'h0, 1'b1);
    send_directed(4'hd, 4'h3, 1'b1);
    send_directed(4'hd, 4'h7, 1'b1);
    send_directed(4'hd, 4'h8, 1'b0);
    send_directed(4'hd, 4'ha, 1'b0);
    send_directed(4'hd, 4'he, 1'b1);
    send_directed(4'he, 4'h4, 1'b0);
    send_directed(4'he, 4'h5, 1'b0);
    send_directed(4'he, 4'h7, 1'b1);
    
    // Bin 71-80
    send_directed(4'he, 4'h9, 1'b1);
    send_directed(4'he, 4'hc, 1'b0);
    send_directed(4'he, 4'hd, 1'b1);
    send_directed(4'hf, 4'h2, 1'b1);
    send_directed(4'hf, 4'h4, 1'b0);
    send_directed(4'hf, 4'h6, 1'b0);
    send_directed(4'hf, 4'h9, 1'b0);
    send_directed(4'hf, 4'ha, 1'b1);
    send_directed(4'hf, 4'hb, 1'b0);
    send_directed(4'hf, 4'hc, 1'b0);
    
    // Bin 81-90
    send_directed(4'hf, 4'hd, 1'b1);
    send_directed(4'hf, 4'he, 1'b1);
    
    // Additional bins from element holes (these have both cin values uncovered)
    // all_1, all_8: a=1, b=8 with both cin
    send_directed(4'h1, 4'h8, 1'b0);
    send_directed(4'h1, 4'h8, 1'b1);
    
    // all_3, all_6: a=3, b=6 with both cin
    send_directed(4'h3, 4'h6, 1'b0);
    send_directed(4'h3, 4'h6, 1'b1);
    
    // all_5, all_b: a=5, b=11 with both cin
    send_directed(4'h5, 4'hb, 1'b0);
    send_directed(4'h5, 4'hb, 1'b1);
    
    // all_6, all_e: a=6, b=14 with both cin
    send_directed(4'h6, 4'he, 1'b0);
    send_directed(4'h6, 4'he, 1'b1);
    
    // all_7, all_c: a=7, b=12 with both cin
    send_directed(4'h7, 4'hc, 1'b0);
    send_directed(4'h7, 4'hc, 1'b1);
    
    // all_8, all_6: a=8, b=6 with both cin
    send_directed(4'h8, 4'h6, 1'b0);
    send_directed(4'h8, 4'h6, 1'b1);
    
    // all_8, all_a: a=8, b=10 with both cin
    send_directed(4'h8, 4'ha, 1'b0);
    send_directed(4'h8, 4'ha, 1'b1);
    
    // all_9, all_7: a=9, b=7 with both cin
    send_directed(4'h9, 4'h7, 1'b0);
    send_directed(4'h9, 4'h7, 1'b1);
    
    // all_b, all_3: a=11, b=3 with both cin
    send_directed(4'hb, 4'h3, 1'b0);
    send_directed(4'hb, 4'h3, 1'b1);
    
    // all_b, all_5: a=11, b=5 with both cin
    send_directed(4'hb, 4'h5, 1'b0);
    send_directed(4'hb, 4'h5, 1'b1);
    
    // all_c, all_a: a=12, b=10 with both cin
    send_directed(4'hc, 4'ha, 1'b0);
    send_directed(4'hc, 4'ha, 1'b1);
    
    `uvm_info("DIRECTED_SEQ", "Completed directed coverage closure sequence - 102 bins targeted", UVM_LOW)
  endtask
  
  // Helper task to send a single directed transaction
  task send_directed(bit [3:0] a_val, bit [3:0] b_val, bit cin_val);
    item m_item;
    m_item = item::type_id::create("m_item");
    start_item(m_item);
    m_item.a = a_val;
    m_item.b = b_val;
    m_item.cin = cin_val;
    finish_item(m_item);
    `uvm_info("DIRECTED_SEQ", $sformatf("Sent: a=%0d, b=%0d, cin=%0d", a_val, b_val, cin_val), UVM_HIGH)
  endtask
endclass


// ============================================================================
// Combined Test: Runs both random and directed sequences
// ============================================================================

class combined_test extends uvm_test;
  `uvm_component_utils(combined_test)
  
  function new(string name = "combined_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  env e0;
  virtual adder_if vif;
  item_seq random_seq;
  directed_item_seq directed_seq;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    e0 = env::type_id::create("e0", this);
    if(!uvm_config_db#(virtual adder_if)::get(this, "", "adder_vif", vif))
      `uvm_fatal("ENV","Virtual interface not found");
    uvm_config_db#(virtual adder_if)::set(this, "e0.a0.*", "adder_vif", vif);
    random_seq = item_seq::type_id::create("random_seq");
    directed_seq = directed_item_seq::type_id::create("directed_seq");
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    
    // First run the original random sequence
    `uvm_info("COMBINED_TEST", "Starting random sequence", UVM_LOW)
    random_seq.randomize();
    random_seq.start(e0.a0.s0);
    
    // Then run directed sequence to fill coverage gaps
    `uvm_info("COMBINED_TEST", "Starting directed sequence for coverage closure", UVM_LOW)
    directed_seq.start(e0.a0.s0);
    
    #1;
    phase.drop_objection(this);
  endtask
endclass


// ============================================================================
// Standalone Directed Test: Only runs directed sequences (for quick verification)
// ============================================================================

class directed_only_test extends uvm_test;
  `uvm_component_utils(directed_only_test)
  
  function new(string name = "directed_only_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  env e0;
  virtual adder_if vif;
  directed_item_seq directed_seq;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    e0 = env::type_id::create("e0", this);
    if(!uvm_config_db#(virtual adder_if)::get(this, "", "adder_vif", vif))
      `uvm_fatal("ENV","Virtual interface not found");
    uvm_config_db#(virtual adder_if)::set(this, "e0.a0.*", "adder_vif", vif);
    directed_seq = directed_item_seq::type_id::create("directed_seq");
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    
    `uvm_info("DIRECTED_TEST", "Running directed sequence only (102 transactions)", UVM_LOW)
    directed_seq.start(e0.a0.s0);
    
    #1;
    phase.drop_objection(this);
  endtask
endclass

module tb_top;
  adder_if _if();
  adder dut(
    .a(_if.a),
    .b(_if.b),
    .cin(_if.cin),
    .sum(_if.sum),
    .cout(_if.cout)
  );
  
  initial begin
    uvm_config_db#(virtual adder_if)::set(null, "*", "adder_vif", _if);
    run_test("test");
  end
endmodule
