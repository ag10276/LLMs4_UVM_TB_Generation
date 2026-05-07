import uvm_pkg::*;
`include "uvm_macros.svh"

class item extends uvm_sequence_item;
  `uvm_object_utils(item)
  
  function new(string name = "item");
    super.new(name);
  endfunction
  
  rand bit[7:0] x;
  rand bit[2:0] s;
  bit [7:0] y;
endclass

class item_seq extends uvm_sequence#(item);
  `uvm_object_utils(item_seq)
  
  function new(string name = "item_seq");
    super.new(name);
  endfunction
  
  rand int num;
  constraint c_num {num inside {[40:50]};}
  
  virtual task body();
    repeat(num) begin
      item q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.randomize();
      finish_item(q_item);
    end
  endtask
endclass

class driver extends uvm_driver#(item);
  `uvm_component_utils(driver)
  
  function new(string name = "driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual bshifter8 vif;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual bshifter8)::get(this, "", "bshifter8_vif", vif))
      `uvm_fatal("DRV", "VIF not found");
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
      item d_item;
      seq_item_port.get_next_item(d_item);
      vif.x = d_item.x;
      vif.s = d_item.s;
      #0;
      seq_item_port.item_done();
      #1;
    end
  endtask
endclass

class monitor extends uvm_monitor;
  `uvm_component_utils(monitor)
  
  function new(string name = "monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual bshifter8 vif;
  uvm_analysis_port#(item) mon_ap;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual bshifter8)::get(this, "", "bshifter8_vif", vif))
      `uvm_fatal("MON", "VIF not found");
    mon_ap = new("mon_ap", this);
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
      item m_item = item::type_id::create("m_item");
      @(vif.x or vif.s);
      #0;
      m_item.x = vif.x;
      m_item.s = vif.s;
      m_item.y = vif.y;
      mon_ap.write(m_item);
    end
  endtask
endclass


class scoreboard extends uvm_scoreboard;
  `uvm_component_utils(scoreboard)
  
  function new(string name = "scoreboard", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  uvm_analysis_imp#(item, scoreboard) sb_imp;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sb_imp = new("sb_imp", this);
  endfunction
  
  logic [7:0] exp_y, a, b;
  
  function void write(item s_item);
    a     = s_item.s[0] ? {1'b0, s_item.x[7:1]} : s_item.x;
    b     = s_item.s[1] ? {2'b00, a[7:2]}       : a;
    exp_y = s_item.s[2] ? {4'b0000, b[7:4]}     : b;
    
    if (exp_y === s_item.y) begin
      `uvm_info("SB",
        $sformatf(
          "MATCH    x=0x%02h (%08b)  s=%0d (%03b)  y=0x%02h (%08b)",
          s_item.x, s_item.x,
          s_item.s, s_item.s,
          s_item.y, s_item.y
        ),
        UVM_LOW
      );
    end
    else begin
      `uvm_error("SB",
        $sformatf(
          {"MISMATCH detected\n",
           "  Input       : x=0x%02h (%08b)\n",
           "  Shift amt   : s=%0d (%03b)\n",
           "  Stage a     : 0x%02h (%08b)   // after shift by 1 if s[0]=1\n",
           "  Stage b     : 0x%02h (%08b)   // after shift by 2 if s[1]=1\n",
           "  Expected y  : 0x%02h (%08b)\n",
           "  Actual y    : 0x%02h (%08b)\n",
           "  Ref (x >> s): 0x%02h (%08b)"},
          s_item.x,   s_item.x,
          s_item.s,   s_item.s,
          a,          a,
          b,          b,
          exp_y,      exp_y,
          s_item.y,   s_item.y,
          (s_item.x >> s_item.s), (s_item.x >> s_item.s)
        )
      );
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
    cp_s: coverpoint fc_item.s {bins all[] = {[0:7]};}
  endgroup
  
  function new(string name = "fun_cov", uvm_component parent = null);
    super.new(name, parent);
    fc_item = item::type_id::create("fc_item");
    cg = new();
  endfunction
  
  virtual function void write(T t);
    fc_item.s = t.s;
    cg.sample();
  endfunction
  
  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    cov = cg.get_inst_coverage();
    `uvm_info(get_type_name(), $sformatf("Coverage: %0.2f%%", cov), UVM_NONE)
  endfunction
endclass

class agent extends uvm_agent;
  `uvm_component_utils(agent)
  
  function new(string name = "agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  driver d0;
  monitor m0;
  uvm_sequencer#(item) s0;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    d0 = driver::type_id::create("d0", this);
    m0 = monitor::type_id::create("m0", this);
    s0 = uvm_sequencer#(item)::type_id::create("s0", this);
  endfunction
  
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    d0.seq_item_port.connect(s0.seq_item_export);
  endfunction
endclass

class env extends uvm_env;
  `uvm_component_utils(env)
  
  function new(string name = "env", uvm_component parent);
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
    a0.m0.mon_ap.connect(sb0.sb_imp);
    a0.m0.mon_ap.connect(fc0.analysis_export);
  endfunction
endclass

class test extends uvm_test;
  `uvm_component_utils(test)
  
  function new(string name = "test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  env e0;
  virtual bshifter8 vif;
  item_seq seq;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    e0 = env::type_id::create("e0", this);
    seq = item_seq::type_id::create("seq", this);
    if(!uvm_config_db#(virtual bshifter8)::get(this, "", "bshifter8_vif", vif))
      `uvm_fatal("ENV", "VIF not found");
    uvm_config_db#(virtual bshifter8)::set(this, "e0.a0.*", "bshifter8_vif", vif);
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    seq.randomize();
    seq.start(e0.a0.s0);
    phase.drop_objection(this);
  endtask
endclass

module tb_top;
  bshifter8 _if();
  barrel_shifter_8 dut(
    .x(_if.x),
    .s(_if.s),
    .y(_if.y)
  );
  
  initial begin
    uvm_config_db#(virtual bshifter8)::set(null, "*", "bshifter8_vif", _if);
    run_test("test");
  end
endmodule
