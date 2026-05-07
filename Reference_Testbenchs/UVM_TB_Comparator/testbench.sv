import uvm_pkg::*;
`include "uvm_macros.svh"

class item extends uvm_sequence_item;
  `uvm_object_utils(item)
  
  function new(string name = "item");
    super.new(name);
  endfunction
  
  rand bit[1:0] a;
  rand bit [1:0] b;
  bit agreaterb;
  bit aequalb;
  bit alesserb;
  
endclass

class item_seq extends uvm_sequence#(item);
  `uvm_object_utils(item_seq)
  
  function new(string name = "item_seq");
    super.new(name);
  endfunction
  
  rand int num;
  constraint c_num {num inside {[2000:3000]};}
  
  virtual task body();
    repeat(num) begin
      item m_item = item::type_id::create("m_item");
      start_item(m_item);
      assert(m_item.randomize());
      finish_item(m_item);
    end
  endtask
endclass

class driver extends uvm_driver#(item);
  `uvm_component_utils(driver)
  
  function new(string name = "driver", uvm_component parent);
    super.new(name, parent);
  endfunction
  
  virtual comp_if vif;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual comp_if)::get(this, "", "comp_vif",vif))
      `uvm_fatal("DRV", "Could not get virtual interface");
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
      item m_item;
      seq_item_port.get_next_item(m_item);
      vif.a = m_item.a;
      vif.b = m_item.b;
      #0;
      seq_item_port.item_done();
      #1;
    end
  endtask
endclass

class monitor extends uvm_monitor;
  `uvm_component_utils(monitor)
  
  function new(string name = "monitor", uvm_component parent);
    super.new(name, parent);
  endfunction
  
  virtual comp_if vif;
  uvm_analysis_port #(item) mon_ap;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual comp_if)::get(this, "", "comp_vif", vif))
      `uvm_fatal("DRV", "Could not get virtual interface");
    mon_ap = new("mon_ap", this);
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
      item m_item = item::type_id::create("m_item");
      @(vif.a or vif.b);
      #0;
      m_item.a = vif.a;
      m_item.b = vif.b;
      m_item.agreaterb = vif.agreaterb;
      m_item.aequalb = vif.aequalb;
      m_item.alesserb = vif.alesserb;
      mon_ap.write(m_item);
    end
  endtask
endclass

class scoreboard extends uvm_scoreboard;
  `uvm_component_utils(scoreboard)
  
  function new(string name = "scoreboard", uvm_component parent);
    super.new(name, parent);
  endfunction
  
  uvm_analysis_imp #(item, scoreboard) sb_imp;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sb_imp = new("sb_imp", this);
  endfunction
  
  function void write(item s_item);
    `uvm_info("SB", $sformatf("a: %0d, b: %0d", s_item.a, s_item.b), UVM_NONE)
    if(s_item.a > s_item.b) begin
      if(s_item.agreaterb == 1'b1 && s_item.aequalb == 1'b0 && s_item.alesserb == 1'b0) begin
        `uvm_info("SB", "Greater SUCCESS: A greater than B", UVM_NONE);
      end
      else begin
        `uvm_error("SB", $sformatf("Greater FAIL: Expected g = %0d, e = %0d, l = %0d; Got g = %0d, e = %0d, l = %0d", 1, 0, 0, s_item.agreaterb, s_item.aequalb, s_item.alesserb)); 
      end
    end else if (s_item.a < s_item.b) begin
      if(s_item.agreaterb == 1'b0 && s_item.aequalb == 1'b0 && s_item.alesserb == 1'b1) begin
        `uvm_info("SB", "Lesser SUCCESS: A lesser than B", UVM_NONE);
      end
      else begin
        `uvm_error("SB", $sformatf("Lesser FAIL: Expected g = %0d, e = %0d, l = %0d; Got g = %0d, e = %0d, l = %0d", 0, 0, 1, s_item.agreaterb, s_item.aequalb, s_item.alesserb)); 
      end
    end else begin
      if(s_item.agreaterb == 1'b0 && s_item.aequalb == 1'b1 && s_item.alesserb == 1'b0) begin
        `uvm_info("SB", "Equal SUCCESS: A equal to B", UVM_NONE);
      end
      else begin
        `uvm_error("SB", $sformatf("Equal FAIL: Expected g = %0d, e = %0d, l = %0d; Got g = %0d, e = %0d, l = %0d", 0, 1, 0, s_item.agreaterb, s_item.aequalb, s_item.alesserb)); 
      end
    end
  endfunction
endclass

class fun_cov extends uvm_subscriber#(item);
  `uvm_component_utils(fun_cov)
  
  typedef item T;
  T m_item;
  real cov;
  
  covergroup cg;
    option.per_instance = 1;
    
    cp_a: coverpoint m_item.a {bins all[] = {[0:3]};}
    cp_b: coverpoint m_item.b {bins all[] = {[0:3]};}
    cp_axb: cross cp_a, cp_b;
  endgroup
  
  function new(string name = "fun_cov", uvm_component parent);
    super.new(name, parent);
    m_item = item::type_id::create("m_item", this);
    cg = new();
  endfunction
  
  virtual function void write (T t);
    m_item.a = t.a;
    m_item.b = t.b;
    cg.sample();
  endfunction
  
  function void report_phase(uvm_phase phase);
    cov = cg.get_inst_coverage();
    `uvm_info(get_type_name(), $sformatf("Coverage: %0.2f%%", cov), UVM_NONE);
  endfunction
endclass

class agent extends uvm_agent;
  `uvm_component_utils(agent)
  
  monitor m0;
  driver d0;
  uvm_sequencer#(item) s0;
  
  function new(string name = "agent", uvm_component parent);
    super.new(name, parent);
  endfunction
  
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
 
  agent a0;
  scoreboard sb0;
  fun_cov fc0;
  
  function new(string name ="env", uvm_component parent);
    super.new(name, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    a0 = agent::type_id::create("a0", this);
    sb0 = scoreboard::type_id::create("sb0", this);
    fc0 = fun_cov::type_id::create("fc0", this);
  endfunction
  
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    a0.m0.mon_ap.connect(sb0.sb_imp);
    a0.m0.mon_ap.connect(fc0.analysis_export);
  endfunction
endclass

class test extends uvm_test;
  `uvm_component_utils(test)
  
  env e0;
  item_seq seq;
  
  virtual comp_if vif;
  
  function new(string name = "test", uvm_component parent);
    super.new(name, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    e0 = env::type_id::create("e0", this);
    if(!uvm_config_db#(virtual comp_if)::get(this, "", "comp_vif", vif))
      `uvm_fatal("TEST", "Could not get virtual interface");
    uvm_config_db#(virtual comp_if)::set(this, "e0.a0.*", "comp_vif", vif);
    seq = item_seq::type_id::create("seq");
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    seq.randomize();
    seq.start(e0.a0.s0);
    phase.drop_objection(this);
  endtask
endclass

module tb_top;
  comp_if _if();
  comparator dut(
    .a(_if.a),
    .b(_if.b),
    .agreaterb(_if.agreaterb),
    .aequalb(_if.aequalb),
    .alesserb(_if.alesserb)
  );
  
  initial begin
    uvm_config_db#(virtual comp_if)::set(null, "*", "comp_vif", _if);
    run_test("test");
  end
endmodule