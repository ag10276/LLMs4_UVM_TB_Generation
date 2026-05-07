import uvm_pkg::*;
`include "uvm_macros.svh"

class item extends uvm_sequence_item;
  `uvm_object_utils(item)
  
  randc logic [3:0] in0;
  randc logic [3:0] in1;
  randc logic [3:0] in2;
  randc logic [3:0] in3;
  randc logic [1:0] sel;
  logic [3:0] out;
  
  function new(string name = "item");
    super.new(name);
  endfunction
  
  constraint c_in0 {in0 inside {[0:15]};}
  constraint c_in1 {in1 inside {[0:15]};}
  constraint c_in2 {in2 inside {[0:15]};}
  constraint c_in3 {in3 inside {[0:15]};}
  constraint c_sel {sel inside {[0:3]};}
  
endclass

class item_seq extends uvm_sequence#(item);
  `uvm_object_utils(item_seq)
  
  function new(string name = "item_seq");
    super.new(name);
  endfunction
  
  rand int num;
  constraint c_num {num inside {[400:600]};}
  
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
  function new(string name ="driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual mux_if vif;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual mux_if)::get(this,"","mux_vif", vif))
      `uvm_fatal("DRV", "Virtual Interface not found");      
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
      item m_item;
      seq_item_port.get_next_item(m_item);
      vif.in0 = m_item.in0;
      vif.in1 = m_item.in1;
      vif.in2 = m_item.in2;
      vif.in3 = m_item.in3;
      vif.sel = m_item.sel;
      #0;
      seq_item_port.item_done();
      #1;
    end
  endtask
      
endclass

class monitor extends uvm_monitor;
  `uvm_component_utils(monitor)
  function new(string name ="monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual mux_if vif;
  uvm_analysis_port #(item) mon_ap;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual mux_if)::get(this,"","mux_vif", vif))
      `uvm_fatal("MON", "Virtual Interface not found");
    mon_ap = new("mon_ap", this);
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
      item m_item = item::type_id::create("m_item");
      @(vif.in0 or vif.in1 or vif.in2 or vif.in3 or vif.sel);
      #0;
      m_item.in0 = vif.in0;
      m_item.in1 = vif.in1;
      m_item.in2 = vif.in2;
      m_item.in3 = vif.in3;
      m_item.sel = vif.sel;
      m_item.out = vif.out;
      mon_ap.write(m_item);
      //#1;
    end
  endtask
endclass

class scoreboard extends uvm_scoreboard;
  `uvm_component_utils(scoreboard)
  function new(string name = "scoreboard", uvm_component parent);
    super.new(name, parent);
  endfunction
  
  uvm_analysis_imp#(item, scoreboard) scb_imp;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    scb_imp = new("scb_imp", this);
  endfunction
  
  function void write(item s_item);
    case(s_item.sel)
      2'b00: begin
        if(s_item.out == s_item.in0) begin
          `uvm_info("SCB", "S00: Expected Output", UVM_LOW);
          end else begin
          `uvm_error("SCB", "S00: Not the Expected Output");
          end
      end
        
      2'b01: begin
        if(s_item.out == s_item.in1) begin
          `uvm_info("SCB", "S01: Expected Output", UVM_LOW);
          end else begin
          `uvm_error("SCB", "S01: Not the Expected Output");
          end
      end
      
      2'b10: begin
        if(s_item.out == s_item.in2) begin
          `uvm_info("SCB", "S10: Expected Output", UVM_LOW);
          end else begin
          `uvm_error("SCB", "S10: Not the Expected Output");
          end
      end
      
      2'b11: begin
        if(s_item.out == s_item.in3) begin
          `uvm_info("SCB", "S11: Expected Output", UVM_LOW);
          end else begin
          `uvm_error("SCB", "S11: Not the Expected Output");
          end
      end
      
    endcase  
  endfunction 
endclass

class fun_cov extends uvm_subscriber#(item);
  `uvm_component_utils(fun_cov)
  
  typedef item T;
  T    m_item;
  real cov;
  
  covergroup cg;
    option.per_instance = 1;
    cp_sel : coverpoint m_item.sel {
      bins s00 = {2'b00};
      bins s01 = {2'b01};
      bins s10 = {2'b10};
      bins s11 = {2'b11};
    }
    
    cp_in0: coverpoint m_item.in0 {bins all[] = {[0:15]};}
    cp_in1: coverpoint m_item.in1 {bins all[] = {[0:15]};}
    cp_in2: coverpoint m_item.in2 {bins all[] = {[0:15]};}
    cp_in3: coverpoint m_item.in3 {bins all[] = {[0:15]};}
    
    cx_sel_in0 : cross cp_sel, cp_in0 {bins valid_sel0 = binsof(cp_sel) intersect {2'b00};}
    cx_sel_in1 : cross cp_sel, cp_in1 {bins valid_sel1 = binsof(cp_sel) intersect {2'b01};}
    cx_sel_in2 : cross cp_sel, cp_in2 {bins valid_sel2 = binsof(cp_sel) intersect {2'b10};}
    cx_sel_in3 : cross cp_sel, cp_in3 {bins valid_sel3 = binsof(cp_sel) intersect {2'b11};}
  endgroup
    
  function new(string name = "fun_cov", uvm_component parent = null);
    super.new(name, parent);
    m_item = item::type_id::create("m_item", this);
    cg = new();
  endfunction
  	
  virtual function void write(T t);
    m_item.in0 = t.in0;
  m_item.in1 = t.in1;
  m_item.in2 = t.in2;
  m_item.in3 = t.in3;
  m_item.sel = t.sel;
    cg.sample();
  endfunction
  
  function void report_phase(uvm_phase phase);
    cov = cg.get_inst_coverage ();
    `uvm_info(get_type_name(), $sformatf("Coverage is: %0.2f%%", cov), UVM_MEDIUM)
  endfunction
  
endclass

class agent extends uvm_agent;
  `uvm_component_utils(agent)
  function new(string name="agent", uvm_component parent);
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
  scoreboard sb0;
  fun_cov fc0;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    a0 = agent::type_id::create("a0", this);
    sb0 = scoreboard::type_id::create("sb0", this);
    fc0 = fun_cov::type_id::create("fc0", this);
  endfunction
  
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    a0.m0.mon_ap.connect(sb0.scb_imp);
    a0.m0.mon_ap.connect(fc0.analysis_export);
  endfunction
  
endclass

class test extends uvm_test;
  `uvm_component_utils(test)
  function new(string name="env", uvm_component parent);
    super.new(name, parent);
  endfunction
  
  env e0;
  virtual mux_if vif;
  item_seq seq;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    e0 = env::type_id::create("e0", this);
    if(!uvm_config_db#(virtual mux_if)::get(this, "", "mux_vif", vif))
      `uvm_fatal("TEST", "Could not get VIF");
    uvm_config_db#(virtual mux_if)::set(this, "e0.a0.*", "mux_vif", vif);
    seq = item_seq::type_id::create("seq");
  	//seq.randomize();
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    seq.randomize();
    seq.start(e0.a0.s0);
    #1;
    phase.drop_objection(this);
  endtask  
endclass

module tb_top;
  mux_if _if();
  mux4to1 dut(.in0(_if.in0),
              .in1(_if.in1),
              .in2(_if.in2),
              .in3(_if.in3),
              .sel(_if.sel),
              .out(_if.out)
             );
  initial begin
    _if.in0 = 0;
    _if.in1 = 0;
    _if.in2 = 0;
    _if.in3 = 0;
    _if.sel = 0;
  	uvm_config_db#(virtual mux_if)::set(null, "uvm_test_top","mux_vif", _if);
  	run_test("test");
  end
endmodule
  
