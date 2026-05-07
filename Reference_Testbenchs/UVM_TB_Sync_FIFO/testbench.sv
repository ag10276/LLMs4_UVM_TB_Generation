import uvm_pkg::*;
`include "uvm_macros.svh"

class item extends uvm_sequence_item;
  `uvm_object_utils(item)
  
  function new(string name = "item");
    super.new(name);
  endfunction

  rand bit rst_n;
  rand bit w_en;
  rand bit r_en;
  rand bit [7:0] wr_data;
  logic [7:0] rd_data;
  logic full;
  logic empty;
  
  constraint c_ctrl {
  {w_en, r_en} dist {
    2'b00 := 1,
    2'b01 := 3,
    2'b10 := 3,
    2'b11 := 1
  };
}
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
    q_item.rst_n = 1'b0;
    finish_item(q_item);
    //deassert clr
    q_item = item::type_id::create("q_item");
    start_item(q_item);
    q_item.rst_n = 1'b1;
    finish_item(q_item);
    //start operation
    repeat(num) begin
      item q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.randomize() with {rst_n == 1'b1;};
      apply_mode(q_item);
      finish_item(q_item);
    end
  endtask
endclass

class write_fifo extends item_seq;
  `uvm_object_utils(write_fifo)
  
  function new(string name = "write_fifo");
    super.new(name);
  endfunction
  
  virtual function void apply_mode(item q_item);
    q_item.w_en = 1'b1;
    q_item.r_en = 1'b0;
  endfunction
endclass

class read_fifo extends item_seq;
  `uvm_object_utils(read_fifo)
  
  function new(string name = "read_fifo");
    super.new(name);
  endfunction
  
  virtual function void apply_mode(item q_item);
    q_item.w_en = 1'b0;
    q_item.r_en = 1'b1;
  endfunction
endclass

class driver extends uvm_driver#(item);
  `uvm_component_utils(driver)
  
  function new(string name = "driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual sync_fifo_if vif;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual sync_fifo_if)::get(this, "", "sync_fifo_vif", vif))
      `uvm_fatal("DRV", "Virtual Interface not found!");
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
      item d_item;
      seq_item_port.get_next_item(d_item);
      @(vif.cb);
      vif.cb.rst_n <= d_item.rst_n;
      vif.cb.w_en <= d_item.w_en;
	  vif.cb.r_en <= d_item.r_en;
	  vif.cb.wr_data <= d_item.wr_data;
      //safeguards
//       if (d_item.w_en) begin
//     	if (!vif.cb.full)
//           `uvm_info("DRV", "Write allowed because FIFO is not FULL", UVM_MEDIUM)
//       	else
//       `uvm_error("DRV", "Write blocked because FIFO is FULL")
//   	  end

//       if (d_item.r_en) begin
//         if (!vif.cb.empty)
//           `uvm_info("DRV", "Read allowed because FIFO is not EMPTY", UVM_MEDIUM)
//         else
//           `uvm_error("DRV", "Read blocked because FIFO is EMPTY")
//       end
      seq_item_port.item_done();
    end
  endtask
endclass

class monitor extends uvm_monitor;
  `uvm_component_utils(monitor)
  
  function new(string name = "monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual sync_fifo_if vif;
  uvm_analysis_port #(item) mon_ap;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual sync_fifo_if)::get(this, "", "sync_fifo_vif", vif))
      `uvm_fatal("MON", "Virtual Interface not found!");
    mon_ap = new("mon_ap", this);
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
      item m_item = item::type_id::create("m_item");
      @(vif.cb);
      m_item.rst_n = vif.rst_n;
      m_item.w_en = vif.w_en;
      m_item.r_en = vif.r_en;
      m_item.wr_data = vif.wr_data;
      m_item.rd_data = vif.rd_data;
      m_item.full = vif.full;
      m_item.empty = vif.empty;
      `uvm_info("MON",
  $sformatf("rst_n=%0b w_en=%0b r_en=%0b wr_data=0x%0h rd_data=0x%0h full=%0b empty=%0b",
            m_item.rst_n, m_item.w_en, m_item.r_en,
            m_item.wr_data, m_item.rd_data,
            m_item.full, m_item.empty),
  UVM_LOW)
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
  logic [7:0] exp_fifo[$];
  logic [7:0] exp_rd_data;
  logic exp_full;
  logic exp_empty;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sb_imp = new("sb_imp", this);
    
  endfunction
  
  function void write(item s_item);
    bit write_accept;
    bit read_accept;
    logic [7:0] exp_fifo_pop;
    
    if (!s_item.rst_n) begin
      exp_fifo.delete();
      exp_rd_data = '0;
      exp_empty   = 1'b1;
      exp_full    = 1'b0;
      return;
    end
    
    exp_empty = (exp_fifo.size() == 0);
    exp_full  = (exp_fifo.size() == 8);
    
    write_accept = s_item.w_en && !exp_full;
    read_accept  = s_item.r_en && !exp_empty;
    
    if (read_accept) begin
      exp_fifo_pop = exp_fifo.pop_front();

      if (s_item.rd_data !== exp_fifo_pop) begin
        `uvm_error("SB", $sformatf("RD_DATA mismatch | exp=0x%0h act=0x%0h", exp_fifo_pop, s_item.rd_data))
      end
      else begin
        `uvm_info("SB", $sformatf("READ OK | data=0x%0h", s_item.rd_data), UVM_LOW)
      end
    end
    
    if (write_accept) begin
      exp_fifo.push_back(s_item.wr_data);
      `uvm_info("SB", $sformatf("WRITE OK | data=0x%0h", s_item.wr_data), UVM_LOW)
    end
    
    if (s_item.w_en && exp_full) begin
      `uvm_info("SB", "WRITE blocked by FULL", UVM_LOW)
    end

    if (s_item.r_en && exp_empty) begin
      `uvm_info("SB", "READ blocked by EMPTY", UVM_LOW)
    end
  endfunction
  
endclass

class func_cov extends uvm_subscriber#(item);
  `uvm_component_utils(func_cov)
  
  typedef item T;
  T f_item;
  real cov;
  
  covergroup cg;
	option.per_instance = 1;
    cp_rst_n : coverpoint f_item.rst_n {bins all[] = {[0:1]};}                                            
    cp_w_en : coverpoint f_item.w_en {bins all[] = {[0:1]};}
    cp_r_en : coverpoint f_item.r_en {bins all[] = {[0:1]};}
    cp_full : coverpoint f_item.full {bins all[] = {[0:1]};}
    cp_empty : coverpoint f_item.empty {bins all[] = {[0:1]};}                                                
  endgroup
  
  function new(string name = "func_cov", uvm_component parent = null);
    super.new(name, parent);
    f_item = item::type_id::create("f_item");
    cg = new();
  endfunction
  
  virtual function void write(T t);
    f_item.rst_n = t.rst_n;
    f_item.w_en = t.w_en;
    f_item.r_en = t.r_en;
    f_item.full = t.full;
    f_item.empty = t.empty;
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
  virtual sync_fifo_if vif;
  item_seq seq;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual sync_fifo_if)::get(this, "", "sync_fifo_vif", vif))
      `uvm_fatal("ENV", "Virtual Interface not found!");
    uvm_config_db#(virtual sync_fifo_if)::set(this, "e0.a0.*", "sync_fifo_vif", vif);
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
        
class write_test extends base_test;
  `uvm_component_utils(write_test)

  function new(string name="write_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    item_seq::type_id::set_type_override(write_fifo::get_type());
    super.build_phase(phase);
  endfunction
endclass

class read_test extends base_test;
  `uvm_component_utils(read_test)

  function new(string name="read_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    item_seq::type_id::set_type_override(read_fifo::get_type());
    super.build_phase(phase);
  endfunction
endclass
        

module tb_top;
  logic clk;
  always #10 clk = ~clk;
  
  sync_fifo_if _if(clk);
  sync_fifo dut (
    .clk(clk),
    .rst_n(_if.rst_n),
    .w_en(_if.w_en),
    .r_en(_if.r_en),
    .wr_data(_if.wr_data),
    .rd_data(_if.rd_data),
    .full(_if.full),
    .empty(_if.empty)
  );
  
  initial begin
    clk <=0;
     _if.rst_n = 1'b0;
    uvm_config_db#(virtual sync_fifo_if)::set(null, "*", "sync_fifo_vif", _if);
    run_test("base_test"); 
  end
  
endmodule
