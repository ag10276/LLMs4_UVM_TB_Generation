import uvm_pkg::*;
`include "uvm_macros.svh"
 
class item #(int N = 4) extends uvm_sequence_item;
    `uvm_object_param_utils(item#(N))
 
    rand bit rst_n;
    rand bit [N-1:0] req;
    bit [N-1:0] grant;
 
    constraint c_rst  { rst_n dist {0 := 5, 1 := 95}; }
    constraint c_req  { req != 0; }
 
    function new(string name = "item");
        super.new(name);
    endfunction
 
    function string convert2string();
        return $sformatf("rst_n=%0b req=%04b grant=%04b", rst_n, req, grant);
    endfunction
endclass
 
class item_seq #(int N = 4) extends uvm_sequence#(item#(N));
    `uvm_object_param_utils(item_seq#(N))
 
    rand int unsigned num;
  	constraint c_num { num inside {[75:100]}; }
 
    function new(string name = "item_seq");
        super.new(name);
    endfunction
 
    virtual task body();
        repeat(num) begin
            item#(N) m_item = item#(N)::type_id::create("m_item");
            start_item(m_item);
            assert(m_item.randomize());
            finish_item(m_item);
        end
    endtask
endclass
 
class single_req_seq #(int N = 4) extends uvm_sequence#(item#(N));
    `uvm_object_param_utils(single_req_seq#(N))
 
    rand int unsigned num;
    constraint c_num { num inside {[100:300]}; }
 
    function new(string name = "single_req_seq");
        super.new(name);
    endfunction
 
    virtual task body();
        repeat(num) begin
            item#(N) m_item = item#(N)::type_id::create("m_item");
            start_item(m_item);
            assert(m_item.randomize() with { $onehot(req); rst_n == 1; });
            finish_item(m_item);
        end
    endtask
endclass
 
class burst_seq #(int N = 4) extends uvm_sequence#(item#(N));
    `uvm_object_param_utils(burst_seq#(N))
 
    rand int unsigned num;
    constraint c_num { num inside {[100:300]}; }
 
    function new(string name = "burst_seq");
        super.new(name);
    endfunction
 
    virtual task body();
        repeat(num) begin
            item#(N) m_item = item#(N)::type_id::create("m_item");
            start_item(m_item);
            assert(m_item.randomize() with { req == '1; rst_n == 1; });
            finish_item(m_item);
        end
    endtask
endclass
 
class driver #(int N = 4) extends uvm_driver#(item#(N));
    `uvm_component_param_utils(driver#(N))
 
    virtual arb_if#(N) vif;
 
    function new(string name = "driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction
 
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual arb_if#(N))::get(this, "", "arb_vif", vif))
            `uvm_fatal("DRV", "Virtual interface not found in config db")
    endfunction
 
    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        vif.cb_drv.rst_n <= 0;
        vif.cb_drv.req   <= '0;
        forever begin
            item#(N) m_item;
            seq_item_port.get_next_item(m_item);
            @(vif.cb_drv);
            vif.cb_drv.rst_n <= m_item.rst_n;
            vif.cb_drv.req   <= m_item.req;
            seq_item_port.item_done();
        end
    endtask
endclass
 
class monitor #(int N = 4) extends uvm_monitor;
    `uvm_component_param_utils(monitor#(N))
 
    uvm_analysis_port#(item#(N)) mon_ap;
    virtual arb_if#(N) vif;
 
    function new(string name = "monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction
 
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual arb_if#(N))::get(this, "", "arb_vif", vif))
            `uvm_fatal("MON", "Virtual interface not found in config db")
        mon_ap = new("mon_ap", this);
    endfunction
 
    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        forever begin
            item#(N) m_item = item#(N)::type_id::create("m_item");
            @(vif.cb_mon);
            m_item.rst_n  = vif.cb_mon.rst_n;
            m_item.req    = vif.cb_mon.req;
            m_item.grant  = vif.cb_mon.grant;
            mon_ap.write(m_item);
        end
    endtask
endclass
 
class scoreboard #(int N = 4) extends uvm_scoreboard;
    `uvm_component_param_utils(scoreboard#(N))
 
    uvm_analysis_imp#(item#(N), scoreboard#(N)) sb_imp;
 
    logic [N-1:0] ref_ptr;
    logic [N-1:0] exp_grant;
    bit first_cycle;
 
    int unsigned pass_count;
    int unsigned fail_count;
 
    function new(string name = "scoreboard", uvm_component parent);
        super.new(name, parent);
    endfunction
 
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sb_imp      = new("sb_imp", this);
        ref_ptr     = {{(N-1){1'b0}}, 1'b1};
        exp_grant   = '0;
        first_cycle = 1;
    endfunction
 
    function automatic logic [N-1:0] ref_grant(
        input logic [N-1:0] req,
        input logic [N-1:0] ptr
    );
        logic [N-1:0] mask       = ~(ptr - 1'b1);
        logic [N-1:0] masked_req = req & mask;
        logic [N-1:0] g;
        if (|masked_req)
            g = masked_req & (~masked_req + 1'b1);
        else
            g = req & (~req + 1'b1);
        return g;
    endfunction
 
    function automatic logic [N-1:0] ref_next_ptr(
        input logic [N-1:0] grant,
        input logic [N-1:0] ptr
    );
        if (|grant)
            return {grant[N-2:0], grant[N-1]};
        else
            return ptr;
    endfunction
 
    function void write(item#(N) s_item);
    logic [N-1:0] curr_exp_grant;

    if (!s_item.rst_n) begin
        ref_ptr = {{(N-1){1'b0}}, 1'b1};
        `uvm_info("SB", "Reset detected - reference model re-synced", UVM_MEDIUM)
        return;
    end

    curr_exp_grant = ref_grant(s_item.req, ref_ptr);

    if (s_item.grant !== curr_exp_grant) begin
        `uvm_error("SB", $sformatf(
            "MISMATCH | req=%04b | expected grant=%04b | actual grant=%04b | ptr was=%04b",
            s_item.req, curr_exp_grant, s_item.grant, ref_ptr))
        fail_count++;
    end
    else begin
        `uvm_info("SB", $sformatf(
            "MATCH | req=%04b | expected grant=%04b | actual grant=%04b | ptr was=%04b",
            s_item.req, curr_exp_grant, s_item.grant, ref_ptr), UVM_MEDIUM)
        pass_count++;
    end

    if (s_item.grant != '0 && !$onehot(s_item.grant)) begin
        `uvm_error("SB", $sformatf(
            "ONEHOT VIOLATION | grant=%04b", s_item.grant))
        fail_count++;
    end

    if ((s_item.grant & s_item.req) !== s_item.grant) begin
        `uvm_error("SB", $sformatf(
            "SPURIOUS GRANT | grant=%04b req=%04b", s_item.grant, s_item.req))
        fail_count++;
    end

    ref_ptr = ref_next_ptr(curr_exp_grant, ref_ptr);
endfunction
  
    virtual function void report_phase(uvm_phase phase);
        `uvm_info("SB", $sformatf(
            "Scoreboard summary — PASS: %0d  FAIL: %0d",
            pass_count, fail_count), UVM_NONE)
    endfunction
endclass
 
class func_cov #(int N = 4) extends uvm_subscriber#(item#(N));
    `uvm_component_param_utils(func_cov#(N))

    item#(N) cov_item;
    real cov;

    covergroup arb_cg;
        option.per_instance = 1;

        cp_req: coverpoint cov_item.req iff (cov_item.rst_n) {
            bins all_req[] = {[1:15]};
        }

        cp_grant: coverpoint cov_item.grant iff (cov_item.rst_n) {
            bins all_grant[] = {1,2,4,8};
        }

        cp_rst: coverpoint cov_item.rst_n {
            bins asserted   = {0};
            bins deasserted = {1};
        }

        cx_req_grant: cross cp_req, cp_grant iff (cov_item.rst_n) {
            // Ignore illegal combinations where grant is not one of the asserted req bits
            ignore_bins illegal =
                binsof(cp_req) intersect {4'h1} && binsof(cp_grant) intersect {4'h2,4'h4,4'h8} ||
                binsof(cp_req) intersect {4'h2} && binsof(cp_grant) intersect {4'h1,4'h4,4'h8} ||
                binsof(cp_req) intersect {4'h3} && binsof(cp_grant) intersect {4'h4,4'h8}      ||
                binsof(cp_req) intersect {4'h4} && binsof(cp_grant) intersect {4'h1,4'h2,4'h8} ||
                binsof(cp_req) intersect {4'h5} && binsof(cp_grant) intersect {4'h2,4'h8}      ||
                binsof(cp_req) intersect {4'h6} && binsof(cp_grant) intersect {4'h1,4'h8}      ||
                binsof(cp_req) intersect {4'h7} && binsof(cp_grant) intersect {4'h8}           ||
                binsof(cp_req) intersect {4'h8} && binsof(cp_grant) intersect {4'h1,4'h2,4'h4} ||
                binsof(cp_req) intersect {4'h9} && binsof(cp_grant) intersect {4'h2,4'h4}      ||
                binsof(cp_req) intersect {4'hA} && binsof(cp_grant) intersect {4'h1,4'h4}      ||
                binsof(cp_req) intersect {4'hB} && binsof(cp_grant) intersect {4'h4}           ||
                binsof(cp_req) intersect {4'hC} && binsof(cp_grant) intersect {4'h1,4'h2}      ||
                binsof(cp_req) intersect {4'hD} && binsof(cp_grant) intersect {4'h2}           ||
                binsof(cp_req) intersect {4'hE} && binsof(cp_grant) intersect {4'h1};
        }
    endgroup

    function new(string name = "func_cov", uvm_component parent);
        super.new(name, parent);
        arb_cg = new();
    endfunction

    function void write(item#(N) t);
        cov_item = t;
        arb_cg.sample();
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        cov = arb_cg.get_inst_coverage();
        `uvm_info("FCOV", $sformatf("Functional Coverage: %0.2f%%", cov), UVM_NONE)
    endfunction
endclass
 
class agent #(int N = 4) extends uvm_agent;
    `uvm_component_param_utils(agent#(N))
 
    monitor#(N)          m0;
    driver#(N)           d0;
    uvm_sequencer#(item#(N)) s0;
 
    function new(string name = "agent", uvm_component parent);
        super.new(name, parent);
    endfunction
 
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m0 = monitor#(N)::type_id::create("m0", this);
        d0 = driver#(N)::type_id::create("d0", this);
        s0 = uvm_sequencer#(item#(N))::type_id::create("s0", this);
    endfunction
 
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        d0.seq_item_port.connect(s0.seq_item_export);
    endfunction
endclass
 
class env #(int N = 4) extends uvm_env;
    `uvm_component_param_utils(env#(N))
 
    agent#(N)       a0;
    scoreboard#(N)  sb0;
    func_cov#(N)    cov0;
 
    function new(string name = "env", uvm_component parent);
        super.new(name, parent);
    endfunction
 
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        a0   = agent#(N)::type_id::create("a0",   this);
        sb0  = scoreboard#(N)::type_id::create("sb0",  this);
        cov0 = func_cov#(N)::type_id::create("cov0", this);
    endfunction
 
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        a0.m0.mon_ap.connect(sb0.sb_imp);
        a0.m0.mon_ap.connect(cov0.analysis_export);
    endfunction
endclass
 
class base_test_base #(int N = 4) extends uvm_test;
    `uvm_component_param_utils(base_test_base#(N))
 
    env#(N)            e0;
    uvm_sequence#(item#(N)) seq;
    virtual arb_if#(N)     vif;
 
    function new(string name = "base_test", uvm_component parent);
        super.new(name, parent);
    endfunction
 
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        e0  = env#(N)::type_id::create("e0", this);
        seq = item_seq#(N)::type_id::create("seq");
        if (!uvm_config_db#(virtual arb_if#(N))::get(this, "", "arb_vif", vif))
            `uvm_fatal("TEST", "Could not get virtual interface from config db")
        uvm_config_db#(virtual arb_if#(N))::set(this, "e0.a0.*", "arb_vif", vif);
    endfunction
 
    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        phase.raise_objection(this);
        apply_reset();
        assert(seq.randomize());
        seq.start(e0.a0.s0);
        phase.drop_objection(this);
    endtask
 
    virtual task apply_reset();
        vif.rst_n <= 0;
        repeat(5) @(posedge vif.clk);
        vif.rst_n <= 1;
        @(posedge vif.clk);
    endtask
endclass
 
class base_test extends base_test_base#(4);
    `uvm_component_utils(base_test)

    function new(string name = "base_test", uvm_component parent);
        super.new(name, parent);
    endfunction
endclass

class single_test extends base_test_base#(4);
    `uvm_component_utils(single_test)

    function new(string name = "single_test", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        seq = single_req_seq#(4)::type_id::create("seq");
    endfunction
endclass

class burst_test extends base_test_base#(4);
    `uvm_component_utils(burst_test)

    function new(string name = "burst_test", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        seq = burst_seq#(4)::type_id::create("seq");
    endfunction
endclass
 
module tb_top;
    localparam int N = 4;
 
    logic clk;
    initial clk = 0;
    always #5 clk = ~clk;
 
    arb_if#(N) _if(.clk(clk));
 
    round_robin_arbiter #(.N(N)) dut (
        .clk   (clk),
        .rst_n (_if.rst_n),
        .req   (_if.req),
        .grant (_if.grant)
    );
 
    initial begin
        uvm_config_db#(virtual arb_if#(N))::set(null, "*", "arb_vif", _if);
        run_test("base_test");
    end
endmodule

