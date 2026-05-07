import uvm_pkg::*;
`include "uvm_macros.svh"

class item extends uvm_sequence_item;
  `uvm_object_utils(item)
  rand bit [7:0] a,b;
  rand bit [2:0] opcode;
  bit [7:0] y;
  bit [3:0] flags;
  
  function new(string name = "item");
    super.new(name);
  endfunction
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
  
  virtual alu_if vif;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual alu_if)::get(this, "", "alu_vif", vif))
      `uvm_fatal("DRV", "VIF not found");
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
      item d_item;
      seq_item_port.get_next_item(d_item);
      vif.a = d_item.a;
      vif.b = d_item.b;
      vif.opcode = d_item.opcode;
      #0;
      seq_item_port.item_done();
      #1;
    end
  endtask
endclass

class monitor extends uvm_monitor;
  `uvm_component_utils(monitor)
  
  function new(string name="monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual alu_if vif;
  uvm_analysis_port#(item) mon_ap;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual alu_if)::get(this, "", "alu_vif", vif))
      `uvm_fatal("MON", "VIF not found");
    mon_ap = new("mon_ap", this);
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
      item m_item = item::type_id::create("m_item");
      @(vif.a or vif.b or vif.opcode);
      #0;
      m_item.a = vif.a;
      m_item.b = vif.b;
      m_item.opcode = vif.opcode;
      m_item.y = vif.y;
      m_item.flags = vif.flags;
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
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sb_imp = new("sb_imp", this);
  endfunction
  
  logic [8:0] exp_y_comp;
  logic [7:0] exp_y;
  logic [3:0] exp_flags;
  
  function void write(item s_item);
    exp_y_comp = 9'b000000000;
    exp_y = 8'b00000000;
    exp_flags = 4'b0000;
    case(s_item.opcode)
      3'b000: begin
        exp_y_comp = {1'b0, s_item.a}+{1'b0, s_item.b};
        exp_y = exp_y_comp[7:0];
        exp_flags[1] = exp_y_comp[8];
        exp_flags[3] = (~s_item.a[7] & ~s_item.b[7] & exp_y[7]) | (s_item.a[7] & s_item.b[7] & ~exp_y[7]); 
      end
      3'b001: begin
        exp_y_comp = {1'b0, s_item.a}+{1'b0, ~s_item.b} +8'b1;
        exp_y = exp_y_comp[7:0];
        exp_flags[1] = exp_y_comp[8];
        exp_flags[3] = (s_item.a[7] & ~s_item.b[7] & ~exp_y[7]) | (~s_item.a[7] & s_item.b[7] & exp_y[7]); 
      end
      3'b010: begin
        exp_y = s_item.a & s_item.b;
      end
      3'b011: begin
        exp_y = s_item.a | s_item.b;
      end
      3'b100: begin
        exp_y = s_item.a ^ s_item.b;
      end
      3'b101: begin
        exp_y = ~s_item.a;
      end
      3'b110: begin
        exp_flags[1] = s_item.a[7];
        exp_y = s_item.a << 1;
      end
      3'b111: begin
        s_item.flags[1] = s_item.a[0];
        exp_y = s_item.a >> 1;
      end
    endcase
    exp_flags[0] = exp_y[7];
    exp_flags[2] = (exp_y == 8'b00000000);
    if(exp_y == s_item.y && exp_flags == s_item.flags) begin
          `uvm_info("SB", "Result as Expected", UVM_NONE);
        end else begin
          `uvm_error("SB", $sformatf("Debug Required -> opcode: %0b", s_item.opcode));
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
    cp_opcode: coverpoint fc_item.opcode {bins all[] = {[0:7]};} 
  endgroup
  
  function new(string name = "fun_cov", uvm_component parent = null);
    super.new(name, parent);
    fc_item = item::type_id::create("fc_item", this);
    cg = new();
  endfunction
  
  virtual function void write(T t);
    fc_item.opcode = t.opcode;
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
  
  function new(string name = "agent", uvm_component parent);
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
  
  function new(string name = "env", uvm_component parent = null);
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
  virtual alu_if vif;
  item_seq seq;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    e0 = env::type_id::create("e0", this);
    if(!uvm_config_db#(virtual alu_if)::get(this, "", "alu_vif", vif))
      `uvm_fatal("ENV", "VIF not found");
    uvm_config_db#(virtual alu_if)::set(this, "e0.a0.*", "alu_vif", vif);
    seq = item_seq::type_id::create("seq", this);
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    seq.randomize();
    seq.start(e0.a0.s0);
    phase.drop_objection(this);
  endtask
endclass

module tb_top;
  alu_if _if();
  alu dut(
    .a(_if.a),
    .b(_if.b),
    .y(_if.y),
    .opcode(_if.opcode),
    .flags(_if.flags)
  );
  
  initial begin
    uvm_config_db#(virtual alu_if)::set(null, "*", "alu_vif", _if);
    run_test("test");
  end
endmodule