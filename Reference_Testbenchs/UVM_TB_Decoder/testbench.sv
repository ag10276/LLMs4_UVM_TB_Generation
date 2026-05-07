import uvm_pkg::*;
`include "uvm_macros.svh"

class item extends uvm_sequence_item;
	`uvm_object_utils(item)

	function new(string name = "item");
		super.new(name);
	endfunction

	randc logic [2:0] a;
	logic [7:0] d;
  
  //constraint c_a {a inside {[0:3]};}
endclass

class item_seq extends uvm_sequence#(item);
	`uvm_object_utils(item_seq)

	function new(string name = "item_seq");
		super.new(name);
	endfunction

	rand int num;
	constraint c_num {num inside {[30:50]};}

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

	function new(string name = "driver", uvm_component parent = null);
		super.new(name, parent);
	endfunction

	virtual decoder_if vif;

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
      if(!uvm_config_db#(virtual decoder_if)::get(this, "", "decoder_vif", vif)) 
		`uvm_fatal("DRV", "Did not get virtual interface");
	endfunction

	virtual task run_phase(uvm_phase phase);
		super.run_phase(phase);
		forever begin
			item m_item;
			seq_item_port.get_next_item(m_item);
			vif.a = m_item.a;
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

	virtual decoder_if vif;
	uvm_analysis_port #(item) mon_ap;

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if(!uvm_config_db#(virtual decoder_if)::get(this, "", "decoder_vif", vif)) 
		`uvm_fatal("MON", "Did not get virtual interface");
		mon_ap = new("mon_ap", this);
	endfunction

	virtual task run_phase(uvm_phase phase);
		super.run_phase(phase);
		forever begin
			item m_item = item::type_id::create("m_item");
			@(vif.a);
			#0;
			m_item.a = vif.a;
			m_item.d = vif.d;
			mon_ap.write(m_item);
		end
	endtask
endclass

class scoreboard extends uvm_scoreboard;
	`uvm_component_utils(scoreboard)

	function new(string name = "scoreboard", uvm_component parent);
		super.new(name, parent);
	endfunction

	uvm_analysis_imp #(item, scoreboard) scb_imp;

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		scb_imp = new("scb_imp", this);
	endfunction

	function void write(item s_item);
		case(s_item.a)
			3'b111: begin
				if(s_item.d == 8'b1000_0000) begin
					`uvm_info("SCB", "111: Output as expected", UVM_NONE)
				end else begin
                  `uvm_error("SCB", $sformatf("Expected: %0b, Got: %0b", 8'b1000_0000, s_item.d))
				end
			end
			3'b110: begin
				if(s_item.d == 8'b0100_0000) begin
					`uvm_info("SCB", "110: Output as expected", UVM_NONE)
				end else begin
                  `uvm_error("SCB", $sformatf("Expected: %0b, Got: %0b", 8'b0100_0000, s_item.d))
				end
			end
			3'b101: begin
				if(s_item.d == 8'b0010_0000) begin
					`uvm_info("SCB", "101: Output as expected", UVM_NONE)
				end else begin
                  `uvm_error("SCB", $sformatf("Expected: %0b, Got: %0b", 8'b0010_0000, s_item.d))
				end
			end
			3'b100: begin
				if(s_item.d == 8'b0001_0000) begin
					`uvm_info("SCB", "100: Output as expected", UVM_NONE)
				end else begin
                  `uvm_error("SCB", $sformatf("Expected: %0b, Got: %0b", 8'b0001_0000, s_item.d))
				end
			end
			3'b011: begin
				if(s_item.d == 8'b0000_1000) begin
					`uvm_info("SCB", "011: Output as expected", UVM_NONE)
				end else begin
                  `uvm_error("SCB", $sformatf("Expected: %0b, Got: %0b", 8'b0000_1000, s_item.d))
				end
			end
			3'b010: begin
				if(s_item.d == 8'b0000_0100) begin
					`uvm_info("SCB", "010: Output as expected", UVM_NONE)
				end else begin
                  `uvm_error("SCB", $sformatf("Expected: %0b, Got: %0b", 8'b0000_0100, s_item.d))
				end
			end
			3'b001: begin
				if(s_item.d == 8'b0000_0010) begin
					`uvm_info("SCB", "001: Output as expected", UVM_NONE)
				end else begin
                  `uvm_error("SCB", $sformatf("Expected: %0b, Got: %0b", 8'b0000_0010, s_item.d))
				end
			end
			3'b000: begin
				if(s_item.d == 8'b0000_0001) begin
					`uvm_info("SCB", "000: Output as expected", UVM_NONE)
				end else begin
                  `uvm_error("SCB", $sformatf("Expected: %0b, Got: %0b", 8'b0000_0001, s_item.d))
				end
			end
			default: begin
				if(s_item.d == 8'b0000_0000) begin
					`uvm_info("SCB", "Default: Output as expected", UVM_NONE)
				end else begin
                  `uvm_error("SCB", $sformatf("Expected: %0b, Got: %0b", 8'b0000_0000, s_item.d))
				end
			end
		endcase
    endfunction
endclass

class fun_cov extends uvm_subscriber#(item);
  `uvm_component_utils(fun_cov)
  
  typedef item T;
  T m_item;
  real cov;
  
  covergroup cg;
    option.per_instance = 1;
    cp_a: coverpoint m_item.a {bins all[] = {[0:7]};}
  endgroup
  
  function new(string name = "fun_cov", uvm_component parent);
    super.new(name, parent);
    m_item = item::type_id::create("m_item");
    cg = new();
  endfunction
  
  virtual function void write(T t);
    m_item.a = t.a;
    cg.sample();
  endfunction
  
  function void report_phase(uvm_phase phase);
    cov = cg.get_inst_coverage();
    `uvm_info(get_type_name(), $sformatf("Coverage is: %0.2f%%", cov), UVM_LOW)
  endfunction
endclass

class agent extends uvm_agent;
	`uvm_component_utils(agent)

	function new(string name="agent", uvm_component parent);
	super.new(name, parent);
	endfunction

	driver d0;
	monitor m0;
	uvm_sequencer #(item) s0;

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
		a0.m0.mon_ap.connect(sb0.scb_imp);
      	a0.m0.mon_ap.connect(fc0.analysis_export);
	endfunction
endclass

class test extends uvm_test;
	`uvm_component_utils(test)

	function new(string name ="test", uvm_component parent);
		super.new(name, parent);
	endfunction

	env e0;
	virtual decoder_if vif;
	item_seq seq;

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
      e0 = env::type_id::create("e0", this);
		if(!uvm_config_db#(virtual decoder_if)::get(this, "", "decoder_vif", vif))
		`uvm_fatal("TEST", "Did not get virtual interface");;
      uvm_config_db#(virtual decoder_if)::set(this, "e0.a0.*", "decoder_vif", vif);
		seq = item_seq::type_id::create("seq");
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
	decoder_if _if();
	decoder dut(.a(_if.a), .d(_if.d));

	initial begin
		uvm_config_db#(virtual decoder_if)::set(null, "*", "decoder_vif", _if);
		run_test("test");
	end
endmodule