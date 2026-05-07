import uvm_pkg::*;
`include "uvm_macros.svh"

class item extends uvm_sequence_item;
  `uvm_object_utils(item)
  
  function new(string name = "item");
    super.new(name);
  endfunction
  
  rand logic clr;
  rand logic [1:0] control;
  rand logic [7:0] parallel_in;
  rand logic serial_in_right;
  rand logic serial_in_left;
  logic serial_out_right;
  logic serial_out_left;
  logic [7:0] parallel_out;
  
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
      q_item.clr = 1'b1;
      q_item.control = 2'b00;
      q_item.parallel_in = '0;
      q_item.serial_in_left = 1'b0;
      q_item.serial_in_right= 1'b0;
    finish_item(q_item);
    //deassert clr
    q_item = item::type_id::create("q_item");
    start_item(q_item);
    q_item.clr = 1'b0;
  	q_item.control = 2'b00; // hold
  	q_item.parallel_in = '0;
  	q_item.serial_in_left = 1'b0;
  	q_item.serial_in_right= 1'b0;
    finish_item(q_item);
    //start operation
    repeat(num) begin
      item q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.randomize() with {clr == 1'b0;};
      apply_mode(q_item);
      finish_item(q_item);
    end
  endtask
endclass

class right_shift_seq extends item_seq;
  `uvm_object_utils(right_shift_seq)
  
  function new(string name = "right_shift_seq");
    super.new(name);
  endfunction
  
  virtual function void apply_mode(item q_item);
    q_item.control = 2'b01;
  endfunction
endclass

class load_hold_seq extends item_seq;
  `uvm_object_utils(load_hold_seq)
  
  function new(string name = "load_hold_seq");
    super.new(name);
  endfunction
  
  virtual task body();
    super.body(); // Reset sequence
    
    // Explicitly test load→hold pattern
    repeat(10) begin
      // Cycle 1: Parallel load
      item q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.clr = 0;
      q_item.control = 2'b11; // Parallel load
      q_item.randomize() with {parallel_in != 0;};
      finish_item(q_item);
      
      // Cycle 2: Hold
      q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.clr = 0;
      q_item.control = 2'b00; // Hold
      q_item.randomize();
      finish_item(q_item);
    end
  endtask
endclass

class left_shift_seq extends item_seq;
  `uvm_object_utils(left_shift_seq)
  
  function new(string name = "left_shift_seq");
    super.new(name);
  endfunction
  
  virtual function void apply_mode(item q_item);
    q_item.control = 2'b10;
  endfunction
endclass

class parallel_seq extends item_seq;
  `uvm_object_utils(parallel_seq)
  
  function new(string name = "parallel_seq");
    super.new(name);
  endfunction
  
  virtual function void apply_mode(item q_item);
    q_item.control = 2'b11;
  endfunction
endclass

class driver extends uvm_driver#(item);
  `uvm_component_utils(driver)
  
  function new(string name = "driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual usr_if vif;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual usr_if)::get(this, "", "usr_vif", vif))
      `uvm_fatal("DRV", "Virtual Interface not found!");
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
      item d_item;
      seq_item_port.get_next_item(d_item);
      @(vif.cb);
      vif.clr <= d_item.clr;
      vif.control <= d_item.control;
      vif.parallel_in <= d_item.parallel_in;
      vif.serial_in_right <= d_item.serial_in_right;
      vif.serial_in_left <= d_item.serial_in_left;
      seq_item_port.item_done();
    end
  endtask
endclass

class monitor extends uvm_monitor;
  `uvm_component_utils(monitor)
  
  function new(string name = "monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual usr_if vif;
  uvm_analysis_port #(item) mon_ap;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual usr_if)::get(this, "", "usr_vif", vif))
      `uvm_fatal("MON", "Virtual Interface not found!");
    mon_ap = new("mon_ap", this);
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
      item m_item = item::type_id::create("m_item");
      @(vif.cb);
      m_item.clr = vif.clr;
      m_item.control = vif.control;
      m_item.parallel_in = vif.parallel_in;
      m_item.serial_in_right = vif.serial_in_right;
      m_item.serial_in_left = vif.serial_in_left;
      m_item.parallel_out = vif.parallel_out;
      m_item.serial_out_right = vif.serial_out_right;
      m_item.serial_out_left = vif.serial_out_left;
      mon_ap.write(m_item);
    end
  endtask
endclass

class scoreboard extends uvm_scoreboard;
  `uvm_component_utils(scoreboard)
  
  logic exp_serial_out_right;
  logic exp_serial_out_left;
  logic [7:0] exp_parallel_out, exp_output;
  
  function new(string name = "scoreboard", uvm_component parent = null);
    super.new(name, parent);
    exp_parallel_out = 'b0;
  endfunction
  
  uvm_analysis_imp #(item, scoreboard) sb_imp;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sb_imp = new("sb_imp", this);
  endfunction
  
  function automatic logic[7:0] next_output(item txn, logic[7:0] curr);
    if(txn.clr) begin
      return 8'b0;
    end else begin
      case(txn.control)
        2'b00: return curr;
        2'b01: return{txn.serial_in_left, curr[7:1]}; //right shift
        2'b10: return{curr[6:0], txn.serial_in_right}; //left shift
        2'b11: return txn.parallel_in; //parallel
        default: begin
        end
      endcase
    end
  endfunction
  
  int unsigned cycle_cnt = 0;

function string mode_str(logic [1:0] ctrl);
  case (ctrl)
    2'b00: return "HOLD";
    2'b01: return "RSHIFT";
    2'b10: return "LSHIFT";
    2'b11: return "PARLOAD";
    default: return "UNKNOWN";
  endcase
endfunction


function void write(item s_item);
  cycle_cnt++;

  // Compute expected
  exp_output = next_output(s_item, exp_parallel_out);
  exp_serial_out_right = exp_output[0];
  exp_serial_out_left  = exp_output[7];

  // Check parallel_out
  if (s_item.parallel_out !== exp_output) begin
    `uvm_error("SB",
      $sformatf(
        "Cycle %0d [%s] parallel_out mismatch | prev=%0h exp=%0h act=%0h",
        cycle_cnt,
        mode_str(s_item.control),
        exp_parallel_out,
        exp_output,
        s_item.parallel_out
      )
    )
  end

  // Check serial_out_right
  if (s_item.serial_out_right !== exp_serial_out_right) begin
    `uvm_error("SB",
      $sformatf(
        "Cycle %0d [%s] serial_out_right mismatch | exp=%0b act=%0b",
        cycle_cnt,
        mode_str(s_item.control),
        exp_serial_out_right,
        s_item.serial_out_right
      )
    )
  end

  // Check serial_out_left
  if (s_item.serial_out_left !== exp_serial_out_left) begin
    `uvm_error("SB",
      $sformatf(
        "Cycle %0d [%s] serial_out_left mismatch | exp=%0b act=%0b",
        cycle_cnt,
        mode_str(s_item.control),
        exp_serial_out_left,
        s_item.serial_out_left
      )
    )
  end
  
  // Update expected state
  exp_parallel_out = exp_output;
endfunction
  
endclass

class func_cov extends uvm_subscriber#(item);
  `uvm_component_utils(func_cov)
  
  typedef item T;
  T f_item;
  real cov;
  
  covergroup cg;
    option.per_instance = 1;
    cp_control: coverpoint f_item.control {bins all[] = {[0:3]};}
  endgroup
  
  function new(string name = "func_cov", uvm_component parent = null);
    super.new(name, parent);
    f_item = item::type_id::create("f_item");
    cg = new();
  endfunction
  
  virtual function void write(T t);
    f_item.control = t.control;
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
  virtual usr_if vif;
  item_seq seq;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual usr_if)::get(this, "", "usr_vif", vif))
      `uvm_fatal("ENV", "Virtual Interface not found!");
    uvm_config_db#(virtual usr_if)::set(this, "e0.a0.*", "usr_vif", vif);
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

class s_right_test extends base_test;
  `uvm_component_utils(s_right_test)

  function new(string name="s_right_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    item_seq::type_id::set_type_override(right_shift_seq::get_type());
    super.build_phase(phase);
  endfunction
endclass

class s_left_test extends base_test;
  `uvm_component_utils(s_left_test)

  function new(string name="s_left_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    item_seq::type_id::set_type_override(left_shift_seq::get_type());
    super.build_phase(phase);
  endfunction
endclass

class p_in_test extends base_test;
  `uvm_component_utils(p_in_test)

  function new(string name="p_in_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    item_seq::type_id::set_type_override(parallel_seq::get_type());
    super.build_phase(phase);
  endfunction
endclass 

class load_hold_test extends base_test;
  `uvm_component_utils(load_hold_test)

  function new(string name = "load_hold_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    item_seq::type_id::set_type_override(load_hold_seq::get_type());
    super.build_phase(phase);
  endfunction
endclass

module tb_top;
  logic clk;
  always #10 clk = ~clk;
  usr_if _if(clk);
  universal_shift_register dut (
    .clk(clk),
    .clr(_if.clr),
    .control(_if.control),
    .parallel_in(_if.parallel_in),
    .serial_in_right(_if.serial_in_right),
    .serial_in_left(_if.serial_in_left),
    .serial_out_right(_if.serial_out_right),
    .serial_out_left(_if.serial_out_left),
    .parallel_out(_if.parallel_out)
  );
  
  initial begin
    clk <=0;
    uvm_config_db#(virtual usr_if)::set(null, "*", "usr_vif", _if);
    run_test("base_test"); 
  end
  
endmodule
