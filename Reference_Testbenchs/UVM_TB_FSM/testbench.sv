import uvm_pkg::*;
`include "uvm_macros.svh"

class item extends uvm_sequence_item;
  `uvm_object_utils(item)
  
  function new(string name = "item");
    super.new(name);
  endfunction

  rand logic reset;
  logic [1:0] light_NS; 
  logic [1:0] light_EW;
  
endclass

class item_seq extends uvm_sequence#(item);
  `uvm_object_utils(item_seq)
  
  function new(string name = "item_seq");
    super.new(name);
  endfunction
  
  rand int num;
  constraint c_num {num inside {[30:50]};}
  
  virtual function void apply_mode(item q_item);
  endfunction
  
  virtual task body();
    //item q_item;
    //assert clr
    item q_item = item::type_id::create("q_item");
    start_item(q_item);
      q_item.reset = 1'b1;
    finish_item(q_item);
    //deassert clr
    q_item = item::type_id::create("q_item");
    start_item(q_item);
    q_item.reset = 1'b0;
    finish_item(q_item);
    //start operation
    repeat(num) begin
      item q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.randomize() with {reset == 1'b0;};
      apply_mode(q_item);
      finish_item(q_item);
    end
  endtask
endclass

class driver extends uvm_driver#(item);
  `uvm_component_utils(driver)
  
  function new(string name = "driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual fsm_if vif;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual fsm_if)::get(this, "", "fsm_vif", vif))
      `uvm_fatal("DRV", "Virtual Interface not found!");
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
      item d_item;
      seq_item_port.get_next_item(d_item);
      @(vif.cb);
      vif.reset <= d_item.reset;
      seq_item_port.item_done();
    end
  endtask
endclass

class monitor extends uvm_monitor;
  `uvm_component_utils(monitor)
  
  function new(string name = "monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual fsm_if vif;
  uvm_analysis_port #(item) mon_ap;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual fsm_if)::get(this, "", "fsm_vif", vif))
      `uvm_fatal("MON", "Virtual Interface not found!");
    mon_ap = new("mon_ap", this);
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
      item m_item = item::type_id::create("m_item");
      @(vif.cb);
      m_item.reset = vif.reset;
      m_item.light_NS = vif.light_NS;
      m_item.light_EW = vif.light_EW;
      mon_ap.write(m_item);
    end
  endtask
endclass

class scoreboard extends uvm_scoreboard;
  `uvm_component_utils(scoreboard)
  
  function new(string name = "scoreboard", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  uvm_analysis_imp #(item, scoreboard) sb_imp;
  
  typedef enum int {EXP_SR, EXP_S0, EXP_S1, EXP_S2, EXP_S3} exp_state_e;
  exp_state_e exp_state;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sb_imp = new("sb_imp", this);
    exp_state = EXP_SR;
  endfunction
  
function void write(item s_item);
  
  logic [1:0] exp_NS, exp_EW;
  string state_name;
  
  if (s_item.reset) begin
      exp_state = EXP_SR;
    end
  case (exp_state)
      EXP_SR: begin
        exp_NS = 2'b00;
        exp_EW = 2'b00;
        state_name = "SR";
      end
      EXP_S0: begin
        exp_NS = 2'b10;
        exp_EW = 2'b00;
        state_name = "S0";
      end
      EXP_S1: begin
        exp_NS = 2'b01;
        exp_EW = 2'b00;
        state_name = "S1";
      end
      EXP_S2: begin
        exp_NS = 2'b00;
        exp_EW = 2'b10;
        state_name = "S2";
      end
      EXP_S3: begin
        exp_NS = 2'b00;
        exp_EW = 2'b01;
        state_name = "S3";
      end
      default: begin
        exp_NS = 2'b00;
        exp_EW = 2'b00;
        state_name = "UNKNOWN";
      end
    endcase
  
  if ((s_item.light_NS !== exp_NS) || (s_item.light_EW !== exp_EW)) begin
    `uvm_error("SB",
        $sformatf("FSM mismatch in %s: expected light_NS=%b light_EW=%b, got light_NS=%b light_EW=%b",
                  state_name, exp_NS, exp_EW, s_item.light_NS, s_item.light_EW))
    end
    else begin
      `uvm_info("SB",
        $sformatf("FSM match in %s: light_NS=%b light_EW=%b",
                  state_name, s_item.light_NS, s_item.light_EW),
        UVM_MEDIUM)
    end
  
  case (exp_state)
      EXP_SR: exp_state = EXP_S0;
      EXP_S0: exp_state = EXP_S1;
      EXP_S1: exp_state = EXP_S2;
      EXP_S2: exp_state = EXP_S3;
      EXP_S3: exp_state = EXP_S0;
      default: exp_state = EXP_SR;
    endcase
  
  
endfunction
  
endclass

class func_cov extends uvm_subscriber#(item);
  `uvm_component_utils(func_cov)
  
  typedef item T;
  T f_item;
  real cov;
  
  covergroup cg;
	option.per_instance = 1;
    cp_reset : coverpoint f_item.reset {bins all[] = {[0:1]};}                                            
    cp_light_NS : coverpoint f_item.light_NS {
      bins red    = {2'b00};
      bins yellow = {2'b01};
      bins green  = {2'b10};
    }
    cp_light_EW : coverpoint f_item.light_EW {
      bins red    = {2'b00};
      bins yellow = {2'b01};
      bins green  = {2'b10};
    }                                                     
  endgroup
  
  function new(string name = "func_cov", uvm_component parent = null);
    super.new(name, parent);
    f_item = item::type_id::create("f_item");
    cg = new();
  endfunction
  
  virtual function void write(T t);
    f_item.reset = t.reset;
    f_item.light_NS = t.light_NS;
    f_item.light_EW = t.light_EW;
    cg.sample();
  endfunction
  
  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    cov = cg.get_inst_coverage();
    `uvm_info("FC", $sformatf("Coverage: %0.2f%%", cov), UVM_NONE)
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
  virtual fsm_if vif;
  item_seq seq;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual fsm_if)::get(this, "", "fsm_vif", vif))
      `uvm_fatal("ENV", "Virtual Interface not found!");
    uvm_config_db#(virtual fsm_if)::set(this, "e0.a0.*", "fsm_vif", vif);
    e0 = env::type_id::create("e0", this);
    seq = item_seq::type_id::create("seq", this);
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    phase.raise_objection(this);
    seq.randomize();
    seq.start(e0.a0.s0);
    phase.drop_objection(this);
  endtask
  
endclass

module tb_top;
  logic clk;
  always #10 clk = ~clk;
  
  fsm_if _if(clk);
  traffic_light_controller dut (
    .clk(clk),
    .reset(_if.reset),
    .light_NS(_if.light_NS),
    .light_EW(_if.light_EW)
  );
  
  initial begin
    clk <=0;
     _if.reset = 1'b1;
    uvm_config_db#(virtual fsm_if)::set(null, "*", "fsm_vif", _if);
    run_test("base_test"); 
  end
  
endmodule
