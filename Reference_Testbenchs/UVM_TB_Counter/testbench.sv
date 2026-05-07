import uvm_pkg::*;
`include "uvm_macros.svh"

class item extends uvm_sequence_item;
  `uvm_object_utils(item)
  
  rand bit rst;
  rand bit up;
  bit [3:0] dout;
  
  constraint c_rst { rst == 0; }
  
  function new(string name = "item");
    super.new(name);
  endfunction
  
endclass

class item_seq extends uvm_sequence#(item);
  `uvm_object_utils(item_seq)
  
  function new (string name = "item_seq");
    super.new(name);
  endfunction
  
  rand int num;
  constraint c_num{num inside {[100:300]};}
  
  virtual task body();
    repeat(num) begin
      item m_item = item::type_id::create("m_item");
      start_item(m_item);
      assert(m_item.randomize());
      finish_item(m_item);
    end
  endtask 
endclass

class up_item_seq extends uvm_sequence#(item);
  `uvm_object_utils(up_item_seq)
  
  function new (string name = "up_item_seq");
    super.new(name);
  endfunction
  
  rand int num;
  constraint c_num{num inside {[100:300]};}
  
  virtual task body();
    repeat(num) begin
      item m_item = item::type_id::create("m_item");
      start_item(m_item);
      assert(m_item.randomize() with {up == 1;});
      finish_item(m_item);
    end
  endtask 
endclass

class down_item_seq extends uvm_sequence#(item);
  `uvm_object_utils(down_item_seq)
  
  function new (string name = "down_item_seq");
    super.new(name);
  endfunction
  
  rand int num;
  constraint c_num{num inside {[100:300]};}
  
  virtual task body();
    repeat(num) begin
      item m_item = item::type_id::create("m_item");
      start_item(m_item);
      assert(m_item.randomize() with {up == 0;});
      finish_item(m_item);
    end
  endtask 
endclass


class driver extends uvm_driver#(item);
  `uvm_component_utils(driver)
  
  function new(string name = "driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual counter_if vif;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual counter_if)::get(this, "", "counter_vif", vif)) `uvm_fatal("DRV", "VIF not found");
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
      item m_item;
      seq_item_port.get_next_item(m_item);
      @(vif.cb_drv);
      vif.cb_drv.rst <= m_item.rst;
      vif.cb_drv.up  <= m_item.up;
      seq_item_port.item_done();
    end
  endtask
endclass


class monitor extends uvm_monitor;
  `uvm_component_utils(monitor)
  
  function new(string name = "monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  uvm_analysis_port#(item) mon_ap;
  virtual counter_if vif;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual counter_if)::get(this, "", "counter_vif", vif)) `uvm_fatal("MON", "Virtual Interface not found");
    mon_ap = new("mon_ap", this);
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
      item m_item = item::type_id::create("m_item");
      @(vif.cb_mon);
      m_item.rst  = vif.cb_mon.rst;
      m_item.up   = vif.cb_mon.up;
      m_item.dout = vif.cb_mon.dout;
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

  bit [3:0] exp_dout;
  bit       prev_rst;
  bit       prev_up;
  bit       prev_valid;

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sb_imp = new("sb_imp", this);

    exp_dout   = 4'd0;
    prev_rst   = 1'b1;
    prev_up    = 1'b0;
    prev_valid = 1'b0;
  endfunction

  function void write(item s_item);
    bit [3:0] expected_now;

    // First sample: just align scoreboard to observed state
    if (!prev_valid) begin
      exp_dout   = s_item.dout;
      prev_rst   = s_item.rst;
      prev_up    = s_item.up;
      prev_valid = 1'b1;

      `uvm_info("SB", $sformatf(
        "INIT: dout=%0d (rst=%0b, up=%0b)",
        s_item.dout, s_item.rst, s_item.up), UVM_LOW)
      return;
    end

    // Current dout should result from PREVIOUS cycle's control
    if (prev_rst)
      expected_now = 4'd0;
    else if (prev_up)
      expected_now = exp_dout + 4'd1;
    else
      expected_now = exp_dout - 4'd1;

    if (s_item.dout !== expected_now) begin
      `uvm_error("SB", $sformatf(
        "Expected %0d, got %0d | prev_rst=%0b prev_up=%0b | curr_rst=%0b curr_up=%0b",
        expected_now, s_item.dout, prev_rst, prev_up, s_item.rst, s_item.up))
    end
    else begin
      `uvm_info("SB", $sformatf(
        "OK: dout=%0d (prev_rst=%0b, prev_up=%0b | curr_rst=%0b, curr_up=%0b)",
        s_item.dout, prev_rst, prev_up, s_item.rst, s_item.up), UVM_LOW)
    end

    // Update model state to the newly observed state
    exp_dout = s_item.dout;
    prev_rst = s_item.rst;
    prev_up  = s_item.up;
  endfunction
endclass

// class functional_coverage extends uvm_subscriber#(item);
// endclass

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
  function new(string name = "env", uvm_component parent);
    super.new(name, parent);
  endfunction
  
  agent a0;
  scoreboard sb0;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    a0 = agent::type_id::create("a0", this);
    sb0 = scoreboard::type_id::create("sb0", this);
  endfunction
  
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    a0.m0.mon_ap.connect(sb0.sb_imp);
  endfunction
endclass

class base_test extends uvm_test;
  `uvm_component_utils(base_test)
  
  function new(string name = "base_test", uvm_component parent);
    super.new(name, parent);
  endfunction
  
  env e0;
  uvm_sequence#(item) seq;
  virtual counter_if vif;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    e0 = env::type_id::create("e0", this);
    seq = item_seq::type_id::create("seq");
    if(!uvm_config_db#(virtual counter_if)::get(this, "", "counter_vif", vif))
      `uvm_fatal("TEST", "Could not get VIF");
    uvm_config_db#(virtual counter_if)::set(this, "e0.a0.*", "counter_vif", vif);
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    phase.raise_objection(this);
    apply_reset();
    seq.randomize();
    seq.start(e0.a0.s0);
    phase.drop_objection(this);
  endtask
  
  virtual task apply_reset();
  vif.rst <= 1;
  vif.up  <= 0;
  repeat(5) @(posedge vif.clk);
  @(negedge vif.clk);
  vif.rst <= 0;
endtask
  
endclass

class up_test extends base_test;
  `uvm_component_utils(up_test)
  
  function new(string name = "up_test", uvm_component parent);
    super.new(name, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    seq = up_item_seq::type_id::create("seq");
  endfunction
endclass

class down_test extends base_test;
  `uvm_component_utils(down_test)
  
  function new(string name = "down_test", uvm_component parent);
    super.new(name, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    seq = down_item_seq::type_id::create("seq");
  endfunction
endclass


module tb_top;
  logic clk;
  always #5 clk = ~clk;
  
  counter_if _if(clk);
  counter dut(
    .clk(clk), 
    .rst(_if.rst),
    .up(_if.up),
    .dout(_if.dout)
  );
  
  initial begin
    clk <=0;
    uvm_config_db#(virtual counter_if)::set(null, "*", "counter_vif", _if);
    run_test("base_test");  
  end
endmodule
