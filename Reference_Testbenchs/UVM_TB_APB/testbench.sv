import uvm_pkg::*;
`include "uvm_macros.svh"

class item extends uvm_sequence_item;
  `uvm_object_utils(item)
  
  function new(string name = "item");
    super.new(name);
  endfunction

  rand bit PRESETn;
  rand bit [31:0] PADDR;
  rand bit [31:0] PWDATA;
  rand bit PWRITE;
  
  bit PSEL;
  bit PENABLE;
  
  bit [31:0] PRDATA;
  bit PREADY;
  bit PSLVERR;
  
  constraint c_reset { PRESETn dist { 1'b1 := 9, 1'b0 := 1 }; }
  constraint c_addr  { PADDR dist { [6'h00:6'h1F] := 7, [6'h20:6'h3F] := 3 }; }
  
  function string convert2string();
    return $sformatf(
      "PRESETn=%0b PWRITE=%0b PADDR=0x%02h PWDATA=0x%08h | PRDATA=0x%08h PREADY=%0b PSLVERR=%0b",
      PRESETn, PWRITE, PADDR, PWDATA, PRDATA, PREADY, PSLVERR);
  endfunction
endclass


class item_seq extends uvm_sequence#(item);
  `uvm_object_utils(item_seq)
  
  function new(string name = "item_seq");
    super.new(name);
  endfunction
  
  rand int unsigned num;
  constraint c_num {num inside {[30:50]};}
  
  virtual function void apply_mode(item q_item);
  endfunction
  
  virtual task body();
    //item q_item;
    //assert resetn
    item q_item = item::type_id::create("q_item");
    start_item(q_item);
    q_item.PRESETn = 1'b0;
    q_item.PSEL = 1'b0;
    q_item.PENABLE = 1'b0;
    finish_item(q_item);
    //deassert resetn
    q_item = item::type_id::create("q_item");
    start_item(q_item);
    q_item.PRESETn = 1'b1;
    q_item.PSEL = 1'b0;
    q_item.PENABLE = 1'b0;
    finish_item(q_item);
    //start operation
    repeat(num) begin
      item q_item = item::type_id::create("q_item");
      start_item(q_item);
      q_item.randomize() with {PRESETn == 1'b1;};
      apply_mode(q_item);
      finish_item(q_item);
    end
  endtask
endclass

class write_seq extends item_seq;
  `uvm_object_utils(write_seq)

  function new(string name = "write_seq");
    super.new(name);
  endfunction

  virtual function void apply_mode(item q_item);
    q_item.PWRITE = 1'b1;
    q_item.PADDR = q_item.PADDR & 6'h1F;   
  endfunction
endclass

class read_seq extends item_seq;
  `uvm_object_utils(read_seq)

  function new(string name = "read_seq");
    super.new(name);
  endfunction

  virtual function void apply_mode(item q_item);
    q_item.PWRITE = 1'b0;
    q_item.PADDR = q_item.PADDR & 6'h1F;  
  endfunction
endclass

class oor_seq extends item_seq;
  `uvm_object_utils(oor_seq)

  function new(string name = "oor_seq");
    super.new(name);
  endfunction

  virtual function void apply_mode(item q_item);
    q_item.PADDR[5] = 1'b1; 
  endfunction
endclass

class driver extends uvm_driver#(item);
  `uvm_component_utils(driver)
  
  function new(string name = "driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual apb_if vif;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual apb_if)::get(this, "", "apb_vif", vif))
      `uvm_fatal("DRV", "Virtual Interface not found!");
  endfunction
  
  task drive_idle();
    vif.drv_cb.PSEL    <= 1'b0;
    vif.drv_cb.PENABLE <= 1'b0;
    vif.drv_cb.PWRITE  <= 1'b0;
    vif.drv_cb.PADDR   <= '0;
    vif.drv_cb.PWDATA  <= '0;
  endtask
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);

    vif.drv_cb.PRESETn <= 1'b1;
    drive_idle();

    forever begin
      item d_item;
      seq_item_port.get_next_item(d_item);

      if (!d_item.PRESETn) begin
        // Apply reset cleanly for one cycle
        @(vif.drv_cb);
        vif.drv_cb.PRESETn <= 1'b0;
        drive_idle();

        @(vif.drv_cb);
        vif.drv_cb.PRESETn <= 1'b1;
        drive_idle();
      end
      else begin
        // -------------------------
        // SETUP phase
        // -------------------------
        @(vif.drv_cb);
        vif.drv_cb.PRESETn <= 1'b1;
        vif.drv_cb.PSEL    <= 1'b1;
        vif.drv_cb.PENABLE <= 1'b0;
        vif.drv_cb.PWRITE  <= d_item.PWRITE;
        vif.drv_cb.PADDR   <= d_item.PADDR;
        vif.drv_cb.PWDATA  <= d_item.PWDATA;

        `uvm_info("DRV_DBG",
          $sformatf("SETUP  @%0t | PWRITE=%0b PADDR=0x%02h PWDATA=0x%08h",
                    $time, d_item.PWRITE, d_item.PADDR, d_item.PWDATA),
          UVM_MEDIUM)

        // -------------------------
        // ACCESS phase
        // -------------------------
        @(vif.drv_cb);
        vif.drv_cb.PSEL    <= 1'b1;
        vif.drv_cb.PENABLE <= 1'b1;

        `uvm_info("DRV_DBG",
          $sformatf("ACCESS @%0t | PWRITE=%0b PADDR=0x%02h",
                    $time, d_item.PWRITE, d_item.PADDR),
          UVM_MEDIUM)

        // Wait until transfer completes
        do @(vif.drv_cb); while (!vif.drv_cb.PREADY);

        d_item.PRDATA  = vif.drv_cb.PRDATA;
        d_item.PREADY  = vif.drv_cb.PREADY;
        d_item.PSLVERR = vif.drv_cb.PSLVERR;

        `uvm_info("DRV_DBG",
          $sformatf("DONE   @%0t | PRDATA=0x%08h PREADY=%0b PSLVERR=%0b",
                    $time, d_item.PRDATA, d_item.PREADY, d_item.PSLVERR),
          UVM_MEDIUM)

        // -------------------------
        // Return to IDLE
        // -------------------------
        @(vif.drv_cb);
        drive_idle();

        `uvm_info("DRV_DBG",
          $sformatf("IDLE   @%0t | drop PSEL/PENABLE", $time),
          UVM_MEDIUM)
      end

      seq_item_port.item_done();
    end
  endtask
endclass

class monitor extends uvm_monitor;
  `uvm_component_utils(monitor)
  
  function new(string name = "monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual apb_if vif;
  uvm_analysis_port #(item) mon_ap;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual apb_if)::get(this, "", "apb_vif", vif))
      `uvm_fatal("MON", "Virtual Interface not found!");
    mon_ap = new("mon_ap", this);
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
      item m_item;
      @(vif.mon_cb);

      // Capture reset 
      if (!vif.mon_cb.PRESETn) begin
        m_item = item::type_id::create("m_item");
        m_item.PRESETn  = 1'b0;
        m_item.PSEL     = 1'b0;
        m_item.PENABLE  = 1'b0;
        m_item.PWRITE   = 1'b0;
        m_item.PADDR    = '0;
        m_item.PWDATA   = '0;
        m_item.PRDATA   = vif.mon_cb.PRDATA;
        m_item.PREADY   = vif.mon_cb.PREADY;
        m_item.PSLVERR  = vif.mon_cb.PSLVERR;
        `uvm_info("MON", $sformatf("RESET observed | PRDATA=0x%08h PREADY=%0b PSLVERR=%0b",
          m_item.PRDATA, m_item.PREADY, m_item.PSLVERR), UVM_LOW)
        mon_ap.write(m_item);

      // Capture completed ACCESS phase
      end else if (vif.mon_cb.PSEL && vif.mon_cb.PENABLE && vif.mon_cb.PREADY) begin
        m_item           = item::type_id::create("m_item");
        m_item.PRESETn   = vif.mon_cb.PRESETn;
        m_item.PWRITE    = vif.mon_cb.PWRITE;
        m_item.PADDR     = vif.mon_cb.PADDR;
        m_item.PWDATA    = vif.mon_cb.PWDATA;
        m_item.PRDATA    = vif.mon_cb.PRDATA;
        m_item.PREADY    = vif.mon_cb.PREADY;
        m_item.PSLVERR   = vif.mon_cb.PSLVERR;
        `uvm_info("MON", m_item.convert2string(), UVM_LOW)
        mon_ap.write(m_item);
      end
    end
  endtask
endclass

class scoreboard extends uvm_scoreboard;
  `uvm_component_utils(scoreboard)
  
  function new(string name = "scoreboard", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  uvm_analysis_imp #(item, scoreboard) sb_imp;
  logic [31:0] exp_mem [31:0];
  int pass_cnt, fail_cnt;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sb_imp = new("sb_imp", this);
  endfunction
  
  function void write(item s_item);
    if (!s_item.PRESETn) begin
      foreach (exp_mem[i]) exp_mem[i] = '0;
      chk("RESET: PRDATA=0", s_item.PRDATA  === 32'h0);
      chk("RESET: PREADY=0", s_item.PREADY  === 1'b0);
      chk("RESET: PSLVERR=0", s_item.PSLVERR === 1'b0);
      return;
    end
    
    if (s_item.PADDR[5]) begin
      chk($sformatf("OOR %s PADDR=0x%02h: PSLVERR=1",
            s_item.PWRITE ? "WRITE" : "READ", s_item.PADDR),
          s_item.PSLVERR === 1'b1);
      if (!s_item.PWRITE)
        chk("OOR READ: PRDATA=0", s_item.PRDATA === 32'h0);
      return;
    end
    
    chk($sformatf("VALID %s PADDR=0x%02h: PSLVERR=0",
          s_item.PWRITE ? "WRITE" : "READ", s_item.PADDR),
        s_item.PSLVERR === 1'b0);

    if (s_item.PWRITE) begin
      exp_mem[s_item.PADDR[4:0]] = s_item.PWDATA;
      `uvm_info("SB", $sformatf("WRITE OK | addr=0x%02h data=0x%08h",
        s_item.PADDR, s_item.PWDATA), UVM_LOW)
    end else begin
      chk($sformatf("READ ADDR=0x%02h data match", s_item.PADDR),
          s_item.PRDATA === exp_mem[s_item.PADDR[4:0]]);
    end
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
    `uvm_info("SB", $sformatf("Scoreboard: %0d PASS  %0d FAIL",
      pass_cnt, fail_cnt), UVM_NONE)
  endfunction
  
endclass

class func_cov extends uvm_subscriber#(item);
  `uvm_component_utils(func_cov)
  
  typedef item T;
  T f_item;
  real cov_signals, cov_transactions, cov_transitions;
  
  logic prev_pwrite;
  logic prev_valid;
  
  covergroup cg_signals;
    option.per_instance = 1;

    cp_resetn  : coverpoint f_item.PRESETn { bins all[] = {[0:1]}; }
    cp_pwrite  : coverpoint f_item.PWRITE  { bins all[] = {[0:1]}; }
    cp_pslverr : coverpoint f_item.PSLVERR { bins all[] = {[0:1]}; }
    cp_pready  : coverpoint f_item.PREADY  { bins all[] = {[0:1]}; }
    cp_addr_range : coverpoint f_item.PADDR[5] {
      bins IN_RANGE  = {1'b0};
      bins OUT_RANGE = {1'b1};
    }
  endgroup
  
  covergroup cg_transactions;
    option.per_instance = 1;

    cp_direction : coverpoint f_item.PWRITE {
      bins READ  = {1'b0};
      bins WRITE = {1'b1};
    }
    cp_range : coverpoint f_item.PADDR[5] {
      bins IN_RANGE  = {1'b0};
      bins OUT_RANGE = {1'b1};
    }
    cp_error : coverpoint f_item.PSLVERR {
      bins NO_ERR = {1'b0};
      bins ERROR  = {1'b1};
    }

    // All four direction x range combinations
    cx_dir_range : cross cp_direction, cp_range;
    cx_dir_error : cross cp_direction, cp_error;
  endgroup
  
  covergroup cg_transitions;
    option.per_instance = 1;

    cp_prev : coverpoint prev_pwrite {
      bins PREV_READ  = {1'b0};
      bins PREV_WRITE = {1'b1};
    }
    cp_curr : coverpoint f_item.PWRITE {
      bins CURR_READ  = {1'b0};
      bins CURR_WRITE = {1'b1};
    }
    cx_b2b : cross cp_prev, cp_curr;
  endgroup
  
  
  
  function new(string name = "func_cov", uvm_component parent = null);
    super.new(name, parent);
    f_item = item::type_id::create("f_item");
    cg_signals     = new();
    cg_transactions = new();
    cg_transitions = new();
    prev_valid  = 1'b0;
    prev_pwrite = 1'b0;
  endfunction
  
  virtual function void write(T t);
    f_item.PRESETn = t.PRESETn;
    f_item.PWRITE = t.PWRITE;
    f_item.PADDR = t.PADDR;
    f_item.PWDATA = t.PWDATA;
    f_item.PRDATA = t.PRDATA;
    f_item.PREADY = t.PREADY;
    f_item.PSLVERR = t.PSLVERR;
    cg_signals.sample();
    if (f_item.PRESETn)
      cg_transactions.sample();
    if (f_item.PRESETn && prev_valid)
      cg_transitions.sample();
    if (!f_item.PRESETn) begin
      prev_valid = 1'b0;
    end else begin
      prev_pwrite = f_item.PWRITE;
      prev_valid  = 1'b1;
    end
  endfunction
  
  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    cov_signals = cg_signals.get_inst_coverage();
    `uvm_info("FC", $sformatf("Coverage Signals: %0.2f%%", cov_signals), UVM_NONE)
    cov_transactions = cg_transactions.get_inst_coverage();
    `uvm_info("FC", $sformatf("Coverage Transactions: %0.2f%%", cov_transactions), UVM_NONE)
    cov_transitions = cg_transitions.get_inst_coverage();
    `uvm_info("FC", $sformatf("Coverage Transistions: %0.2f%%", cov_transitions), UVM_NONE)
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
  virtual apb_if vif;
  item_seq seq;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual apb_if)::get(this, "", "apb_vif", vif))
      `uvm_fatal("ENV", "Virtual Interface not found!");
    uvm_config_db#(virtual apb_if)::set(this, "e0.a0.*", "apb_vif", vif);
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

class reset_test extends base_test;
  `uvm_component_utils(reset_test)

  function new(string name = "reset_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass

class write_test extends base_test;
  `uvm_component_utils(write_test)

  function new(string name = "write_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    item_seq::type_id::set_type_override(write_seq::get_type());
    super.build_phase(phase);
  endfunction
endclass

class write_then_read_test extends base_test;
  `uvm_component_utils(write_then_read_test)

  function new(string name = "write_then_read_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!seq.randomize() with { num == 50; })
      `uvm_fatal("TEST", "seq randomize failed");
  endfunction
endclass

class read_test extends base_test;
  `uvm_component_utils(read_test)

  function new(string name = "read_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    item_seq::type_id::set_type_override(read_seq::get_type());
    super.build_phase(phase);
  endfunction
endclass

class oor_test extends base_test;
  `uvm_component_utils(oor_test)

  function new(string name = "oor_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    item_seq::type_id::set_type_override(oor_seq::get_type());
    super.build_phase(phase);
  endfunction
endclass

module tb_top;
  logic PCLK;
  always #5 PCLK = ~PCLK;

  apb_if _if(PCLK);

  apb_memory dut (
    .PCLK (PCLK),
    .PRESETn (_if.PRESETn),
    .PADDR (_if.PADDR),
    .PWDATA (_if.PWDATA),
    .PSEL (_if.PSEL),
    .PENABLE (_if.PENABLE),
    .PWRITE (_if.PWRITE),
    .PRDATA (_if.PRDATA),
    .PREADY (_if.PREADY),
    .PSLVERR (_if.PSLVERR)
  );

  initial begin
    PCLK = 0;
    uvm_config_db #(virtual apb_if)::set(null, "*", "apb_vif", _if);
    run_test("base_test");
  end

  initial begin
    #500_000;
    `uvm_fatal("TIMEOUT", "Simulation watchdog — check for hangs")
  end
endmodule
      
      



