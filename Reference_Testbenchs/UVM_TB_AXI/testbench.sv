
`include "uvm_macros.svh"
import uvm_pkg::*;

typedef enum logic [2:0] {
  AXI_SIZE_1B  = 3'b000,
  AXI_SIZE_2B  = 3'b001,
  AXI_SIZE_4B  = 3'b010,
  AXI_SIZE_8B  = 3'b011,
  AXI_SIZE_16B = 3'b100
} axsize_e;

localparam logic [1:0] AXI_BURST_FIXED = 2'b00;
localparam logic [1:0] AXI_BURST_INCR  = 2'b01;
localparam logic [1:0] AXI_BURST_WRAP  = 2'b10;
localparam logic [1:0] AXI_BURST_RSVD  = 2'b11;

localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
localparam logic [1:0] AXI_RESP_EXOKAY = 2'b01;
localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;
localparam logic [1:0] AXI_RESP_DECERR = 2'b11;

class axi_item extends uvm_sequence_item;
    `uvm_object_utils_begin(axi_item)
    `uvm_field_int(do_reset,   UVM_DEFAULT)
    `uvm_field_int(is_write,   UVM_DEFAULT)
    `uvm_field_int(id,         UVM_DEFAULT)
    `uvm_field_int(addr,       UVM_DEFAULT)
    `uvm_field_int(len,        UVM_DEFAULT)
    `uvm_field_enum(axsize_e,  size, UVM_DEFAULT)
    `uvm_field_int(raw_burst,  UVM_DEFAULT)
    `uvm_field_array_int(wdata, UVM_DEFAULT)
    `uvm_field_array_int(wstrb, UVM_DEFAULT)
    `uvm_field_array_int(rdata, UVM_DEFAULT)
    `uvm_field_int(bresp,      UVM_DEFAULT)
    `uvm_field_array_int(rresp, UVM_DEFAULT)
  `uvm_object_utils_end

  rand bit          do_reset;
  rand bit          is_write;
  rand bit [3:0]    id;
  rand bit [31:0]   addr;
  rand bit [7:0]    len;
  rand axsize_e     size;
  rand bit [1:0]    raw_burst;

  rand bit [31:0]   wdata[];
  rand bit [3:0]    wstrb[];

  bit [31:0]        rdata[];
  bit [1:0]         bresp;
  bit [1:0]         rresp[];

  constraint c_reset_kind {
    if (do_reset) {
      is_write  == 0;
      id        == 0;
      addr      == 32'h0;
      len       == 0;
      size      == AXI_SIZE_4B;
      raw_burst == AXI_BURST_INCR;
    }
  }

  constraint c_addr {
    addr inside {[32'h0000_0000 : 32'h0000_03FF]};
  }

  constraint c_size {
    size inside {AXI_SIZE_1B, AXI_SIZE_2B, AXI_SIZE_4B};
  }

  constraint c_len {
    len inside {[0:15]};
  }

  // Default legal traffic only. Negative sequences can override by direct assignment.
  constraint c_burst {
    if (!do_reset) raw_burst inside {AXI_BURST_FIXED, AXI_BURST_INCR, AXI_BURST_WRAP};
  }

  // Fixed WRAP legality in the default random item.
  constraint c_wrap {
    if (!do_reset && raw_burst == AXI_BURST_WRAP) {
      len inside {8'h01, 8'h03, 8'h07, 8'h0F};
      (addr & ((1 << size) - 1)) == 0;
    }
  }

  constraint c_data_size {
    wdata.size() == len + 1;
    wstrb.size() == len + 1;
  }

  // default full-word strobes unless sequence overrides
  constraint c_strb {
    foreach (wstrb[i]) wstrb[i] == 4'hF;
  }

  function new(string name = "axi_item");
    super.new(name);
  endfunction
endclass


class axi_base_seq extends uvm_sequence #(axi_item);
  `uvm_object_utils(axi_base_seq)

  rand int unsigned num_txns;
  constraint c_num { soft num_txns inside {[20:40]}; }

  function new(string name = "axi_base_seq");
    super.new(name);
  endfunction

  virtual task send_reset();
    axi_item it = axi_item::type_id::create("reset_item");
    start_item(it);
    it.do_reset  = 1;
    it.is_write  = 0;
    it.id        = 0;
    it.addr      = 0;
    it.len       = 0;
    it.size      = AXI_SIZE_4B;
    it.raw_burst = AXI_BURST_INCR;
    it.wdata     = new[1]; it.wdata[0] = '0;
    it.wstrb     = new[1]; it.wstrb[0] = '0;
    finish_item(it);
  endtask

  virtual task body();
    send_reset();
    repeat (num_txns) begin
      axi_item it = axi_item::type_id::create("txn");
      start_item(it);
      if (!it.randomize() with { do_reset == 0; })
        `uvm_fatal("SEQ", "Randomization failed")
      finish_item(it);
    end
  endtask
endclass

class seq_single_wr_rd extends axi_base_seq;
  `uvm_object_utils(seq_single_wr_rd)

  function new(string name = "seq_single_wr_rd");
    super.new(name);
  endfunction

  virtual task body();
    send_reset();

    repeat (num_txns) begin
      bit [31:0] waddr;
      bit [31:0] wdat;

      waddr = ($urandom_range(0, 255)) * 4;
      wdat  = $urandom();

      begin
        axi_item it = axi_item::type_id::create("wr");
        start_item(it);
        it.do_reset  = 0;
        it.is_write  = 1;
        it.id        = $urandom_range(0, 15);
        it.addr      = waddr;
        it.len       = 0;
        it.size      = AXI_SIZE_4B;
        it.raw_burst = AXI_BURST_INCR;
        it.wdata     = new[1]; it.wdata[0] = wdat;
        it.wstrb     = new[1]; it.wstrb[0] = 4'hF;
        finish_item(it);
      end

      begin
        axi_item it = axi_item::type_id::create("rd");
        start_item(it);
        it.do_reset  = 0;
        it.is_write  = 0;
        it.id        = $urandom_range(0, 15);
        it.addr      = waddr;
        it.len       = 0;
        it.size      = AXI_SIZE_4B;
        it.raw_burst = AXI_BURST_INCR;
        it.wdata     = new[1]; it.wdata[0] = '0;
        it.wstrb     = new[1]; it.wstrb[0] = '0;
        finish_item(it);
      end
    end
  endtask
endclass


class seq_incr4_burst extends axi_base_seq;
  `uvm_object_utils(seq_incr4_burst)
  constraint c_num_ovr { num_txns == 8; }

  function new(string name = "seq_incr4_burst");
    super.new(name);
  endfunction

  virtual task body();
    bit [31:0] base;
    send_reset();

    repeat (num_txns) begin
      base = ($urandom_range(0, 252)) * 4;

      begin
        axi_item it = axi_item::type_id::create("wr_burst");
        start_item(it);
        it.do_reset  = 0;
        it.is_write  = 1;
        it.id        = $urandom_range(0, 15);
        it.addr      = base;
        it.len       = 3;
        it.size      = AXI_SIZE_4B;
        it.raw_burst = AXI_BURST_INCR;
        it.wdata     = new[4];
        it.wstrb     = new[4];
        foreach (it.wdata[i]) begin
          it.wdata[i] = $urandom();
          it.wstrb[i] = 4'hF;
        end
        finish_item(it);
      end

      begin
        axi_item it = axi_item::type_id::create("rd_burst");
        start_item(it);
        it.do_reset  = 0;
        it.is_write  = 0;
        it.id        = $urandom_range(0, 15);
        it.addr      = base;
        it.len       = 3;
        it.size      = AXI_SIZE_4B;
        it.raw_burst = AXI_BURST_INCR;
        it.wdata     = new[4]; foreach (it.wdata[i]) it.wdata[i] = '0;
        it.wstrb     = new[4]; foreach (it.wstrb[i]) it.wstrb[i] = '0;
        finish_item(it);
      end
    end
  endtask
endclass


class seq_narrow_xfer extends axi_base_seq;
  `uvm_object_utils(seq_narrow_xfer)
  constraint c_num_ovr { num_txns == 20; }

  function new(string name = "seq_narrow_xfer");
    super.new(name);
  endfunction

  virtual task body();
    send_reset();

    repeat (num_txns) begin
      axsize_e  sz;
      bit [31:0] baddr;
      bit [3:0]  strb;

      sz = (($urandom() & 1) == 0) ? AXI_SIZE_1B : AXI_SIZE_2B;

      if (sz == AXI_SIZE_1B) begin
        baddr = $urandom_range(0, 1023);
        strb  = 4'b0001 << baddr[1:0];
      end else begin
        baddr = ($urandom_range(0, 511)) * 2;
        strb  = (baddr[1] == 0) ? 4'b0011 : 4'b1100;
      end

      begin
        axi_item it = axi_item::type_id::create("wr_narrow");
        start_item(it);
        it.do_reset  = 0;
        it.is_write  = 1;
        it.id        = $urandom_range(0, 15);
        it.addr      = baddr;
        it.len       = 0;
        it.size      = sz;
        it.raw_burst = AXI_BURST_INCR;
        it.wdata     = new[1]; it.wdata[0] = $urandom();
        it.wstrb     = new[1]; it.wstrb[0] = strb;
        finish_item(it);
      end

      begin
        axi_item it = axi_item::type_id::create("rd_narrow");
        start_item(it);
        it.do_reset  = 0;
        it.is_write  = 0;
        it.id        = $urandom_range(0, 15);
        it.addr      = baddr;
        it.len       = 0;
        it.size      = sz;
        it.raw_burst = AXI_BURST_INCR;
        it.wdata     = new[1]; it.wdata[0] = '0;
        it.wstrb     = new[1]; it.wstrb[0] = '0;
        finish_item(it);
      end
    end
  endtask
endclass


class seq_size_error extends axi_base_seq;
  `uvm_object_utils(seq_size_error)
  constraint c_num_ovr { num_txns == 10; }

  function new(string name = "seq_size_error");
    super.new(name);
  endfunction

  virtual task body();
    send_reset();

    repeat (num_txns) begin
      axi_item it = axi_item::type_id::create("err_txn");
      start_item(it);
      it.do_reset  = 0;
      it.is_write  = $urandom_range(0,1);
      it.id        = $urandom_range(0, 15);
      it.addr      = ($urandom_range(0, 255)) * 4;
      it.len       = 0;
      it.size      = AXI_SIZE_8B;
      it.raw_burst = AXI_BURST_INCR;
      it.wdata     = new[1]; it.wdata[0] = $urandom();
      it.wstrb     = new[1]; it.wstrb[0] = 4'hF;
      finish_item(it);
    end
  endtask
endclass


class seq_narrow_read_lanes extends axi_base_seq;
  `uvm_object_utils(seq_narrow_read_lanes)

  function new(string name = "seq_narrow_read_lanes");
    super.new(name);
  endfunction

  virtual task body();
    bit [31:0] base = 32'h0000_0020;
    send_reset();

    // Seed known word: lane0=A0 lane1=A1 lane2=A2 lane3=A3
    begin
      axi_item it = axi_item::type_id::create("seed_word");
      start_item(it);
      it.do_reset  = 0;
      it.is_write  = 1;
      it.id        = 1;
      it.addr      = base;
      it.len       = 0;
      it.size      = AXI_SIZE_4B;
      it.raw_burst = AXI_BURST_INCR;
      it.wdata     = new[1]; it.wdata[0] = 32'hA3A2A1A0;
      it.wstrb     = new[1]; it.wstrb[0] = 4'hF;
      finish_item(it);
    end

    for (int off = 0; off < 4; off++) begin
      axi_item it = axi_item::type_id::create($sformatf("byte_rd_%0d", off));
      start_item(it);
      it.do_reset  = 0;
      it.is_write  = 0;
      it.id        = 2 + off;
      it.addr      = base + off;
      it.len       = 0;
      it.size      = AXI_SIZE_1B;
      it.raw_burst = AXI_BURST_INCR;
      it.wdata     = new[1]; it.wdata[0] = '0;
      it.wstrb     = new[1]; it.wstrb[0] = '0;
      finish_item(it);
    end

    begin
      axi_item it = axi_item::type_id::create("half_rd_0");
      start_item(it);
      it.do_reset  = 0;
      it.is_write  = 0;
      it.id        = 8;
      it.addr      = base + 0;
      it.len       = 0;
      it.size      = AXI_SIZE_2B;
      it.raw_burst = AXI_BURST_INCR;
      it.wdata     = new[1]; it.wdata[0] = '0;
      it.wstrb     = new[1]; it.wstrb[0] = '0;
      finish_item(it);
    end

    begin
      axi_item it = axi_item::type_id::create("half_rd_2");
      start_item(it);
      it.do_reset  = 0;
      it.is_write  = 0;
      it.id        = 10;
      it.addr      = base + 2;
      it.len       = 0;
      it.size      = AXI_SIZE_2B;
      it.raw_burst = AXI_BURST_INCR;
      it.wdata     = new[1]; it.wdata[0] = '0;
      it.wstrb     = new[1]; it.wstrb[0] = '0;
      finish_item(it);
    end
  endtask
endclass


class seq_illegal_wrap_len extends axi_base_seq;
  `uvm_object_utils(seq_illegal_wrap_len)

  function new(string name = "seq_illegal_wrap_len");
    super.new(name);
  endfunction

  virtual task body();
    send_reset();

    repeat (4) begin
      axi_item it = axi_item::type_id::create("bad_wrap_len");
      start_item(it);
      it.do_reset  = 0;
      it.is_write  = $urandom_range(0,1);
      it.id        = $urandom_range(0,15);
      it.addr      = 32'h0000_0040;
      it.len       = 8'h05; // illegal WRAP length (6 beats)
      it.size      = AXI_SIZE_4B;
      it.raw_burst = AXI_BURST_WRAP;
      it.wdata     = new[it.len+1];
      it.wstrb     = new[it.len+1];
      foreach (it.wdata[i]) begin
        it.wdata[i] = $urandom();
        it.wstrb[i] = 4'hF;
      end
      finish_item(it);
    end
  endtask
endclass


class seq_illegal_wrap_align extends axi_base_seq;
  `uvm_object_utils(seq_illegal_wrap_align)

  function new(string name = "seq_illegal_wrap_align");
    super.new(name);
  endfunction

  virtual task body();
    send_reset();

    repeat (4) begin
      axi_item it = axi_item::type_id::create("bad_wrap_align");
      start_item(it);
      it.do_reset  = 0;
      it.is_write  = $urandom_range(0,1);
      it.id        = $urandom_range(0,15);
      it.addr      = 32'h0000_0042; // misaligned for size=4
      it.len       = 8'h03;         // 4 beats, length is legal
      it.size      = AXI_SIZE_4B;
      it.raw_burst = AXI_BURST_WRAP;
      it.wdata     = new[it.len+1];
      it.wstrb     = new[it.len+1];
      foreach (it.wdata[i]) begin
        it.wdata[i] = $urandom();
        it.wstrb[i] = 4'hF;
      end
      finish_item(it);
    end
  endtask
endclass


class seq_reserved_burst extends axi_base_seq;
  `uvm_object_utils(seq_reserved_burst)

  function new(string name = "seq_reserved_burst");
    super.new(name);
  endfunction

  virtual task body();
    send_reset();

    repeat (6) begin
      axi_item it = axi_item::type_id::create("reserved_burst");
      start_item(it);
      it.do_reset  = 0;
      it.is_write  = $urandom_range(0,1);
      it.id        = $urandom_range(0,15);
      it.addr      = 32'h0000_0080;
      it.len       = 0;
      it.size      = AXI_SIZE_4B;
      it.raw_burst = AXI_BURST_RSVD;
      it.wdata     = new[1]; it.wdata[0] = $urandom();
      it.wstrb     = new[1]; it.wstrb[0] = 4'hF;
      finish_item(it);
    end
  endtask
endclass

class axi_driver extends uvm_driver #(axi_item);
  `uvm_component_utils(axi_driver)

  virtual axi_if vif;

  bit first_aw_printed = 0;
  bit first_ar_printed = 0;

  function new(string name = "axi_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual axi_if)::get(this, "", "axi_vif", vif))
      `uvm_fatal("DRV", "axi_if not found in config_db")
  endfunction

  task idle_all();
    vif.drv_cb.ARESETn <= 1'b1;

    vif.drv_cb.AWVALID <= 1'b0;
    vif.drv_cb.AWID    <= '0;
    vif.drv_cb.AWADDR  <= '0;
    vif.drv_cb.AWLEN   <= '0;
    vif.drv_cb.AWSIZE  <= AXI_SIZE_4B;
    vif.drv_cb.AWBURST <= AXI_BURST_INCR;

    vif.drv_cb.WVALID  <= 1'b0;
    vif.drv_cb.WDATA   <= '0;
    vif.drv_cb.WSTRB   <= '0;
    vif.drv_cb.WLAST   <= 1'b0;

    vif.drv_cb.BREADY  <= 1'b1;

    vif.drv_cb.ARVALID <= 1'b0;
    vif.drv_cb.ARID    <= '0;
    vif.drv_cb.ARADDR  <= '0;
    vif.drv_cb.ARLEN   <= '0;
    vif.drv_cb.ARSIZE  <= AXI_SIZE_4B;
    vif.drv_cb.ARBURST <= AXI_BURST_INCR;

    vif.drv_cb.RREADY  <= 1'b1;
  endtask

  task apply_reset();
    @(vif.drv_cb);
    vif.drv_cb.ARESETn <= 1'b0;
    vif.drv_cb.AWVALID <= 1'b0;
    vif.drv_cb.WVALID  <= 1'b0;
    vif.drv_cb.ARVALID <= 1'b0;
    vif.drv_cb.WLAST   <= 1'b0;
    @(vif.drv_cb);
    @(vif.drv_cb);
    vif.drv_cb.ARESETn <= 1'b1;
    @(vif.drv_cb);
  endtask

  task drive_write(axi_item it);
    int beats = it.len + 1;

    if (!first_aw_printed) begin
      `uvm_info("DRV_AW_FIRST",
        $sformatf("FIRST_DRV_AW id=%0h addr=0x%08h len=%0d size=%0d burst=%0b time=%0t",
                  it.id, it.addr, it.len, it.size, it.raw_burst, $time),
        UVM_MEDIUM)
      first_aw_printed = 1;
    end

    @(vif.drv_cb);
    vif.drv_cb.AWVALID <= 1'b1;
    vif.drv_cb.AWID    <= it.id;
    vif.drv_cb.AWADDR  <= it.addr;
    vif.drv_cb.AWLEN   <= it.len;
    vif.drv_cb.AWSIZE  <= it.size;
    vif.drv_cb.AWBURST <= it.raw_burst;
    do @(vif.drv_cb); while (!vif.drv_cb.AWREADY);
    vif.drv_cb.AWVALID <= 1'b0;

    for (int b = 0; b < beats; b++) begin
      vif.drv_cb.WVALID <= 1'b1;
      vif.drv_cb.WDATA  <= it.wdata[b];
      vif.drv_cb.WSTRB  <= it.wstrb[b];
      vif.drv_cb.WLAST  <= (b == beats-1);

      if (!first_aw_printed) begin
        `uvm_info("DRV_W_FIRST",
          $sformatf("FIRST_DRV_W beat=%0d data=0x%08h strb=0x%0h last=%0b time=%0t",
                    b, it.wdata[b], it.wstrb[b], (b == beats-1), $time),
          UVM_HIGH)
      end

      do @(vif.drv_cb); while (!vif.drv_cb.WREADY);
    end

    vif.drv_cb.WVALID <= 1'b0;
    vif.drv_cb.WLAST  <= 1'b0;

    do @(vif.drv_cb); while (!vif.drv_cb.BVALID);
  endtask

  task drive_read(axi_item it);
    int beats = it.len + 1;

    if (!first_ar_printed) begin
      `uvm_info("DRV_AR_FIRST",
        $sformatf("FIRST_DRV_AR id=%0h addr=0x%08h len=%0d size=%0d burst=%0b time=%0t",
                  it.id, it.addr, it.len, it.size, it.raw_burst, $time),
        UVM_MEDIUM)
      first_ar_printed = 1;
    end

    @(vif.drv_cb);
    vif.drv_cb.ARVALID <= 1'b1;
    vif.drv_cb.ARID    <= it.id;
    vif.drv_cb.ARADDR  <= it.addr;
    vif.drv_cb.ARLEN   <= it.len;
    vif.drv_cb.ARSIZE  <= it.size;
    vif.drv_cb.ARBURST <= it.raw_burst;
    do @(vif.drv_cb); while (!vif.drv_cb.ARREADY);
    vif.drv_cb.ARVALID <= 1'b0;

    for (int b = 0; b < beats; b++) begin
      do @(vif.drv_cb); while (!vif.drv_cb.RVALID);
    end
  endtask

  virtual task run_phase(uvm_phase phase);
    axi_item it;
    @(vif.drv_cb);
    idle_all();
    apply_reset();

    forever begin
      seq_item_port.get_next_item(it);

      if (it.do_reset) begin
        apply_reset();
      end else if (it.is_write) begin
        drive_write(it);
      end else begin
        drive_read(it);
      end

      seq_item_port.item_done();
    end
  endtask
endclass


// =============================================================================
// Monitor
// =============================================================================
class axi_monitor extends uvm_monitor;
  `uvm_component_utils(axi_monitor)

  virtual axi_if vif;
  uvm_analysis_port #(axi_item) mon_ap;

  bit first_obs_aw_printed = 0;
  bit first_obs_ar_printed = 0;

  function new(string name = "axi_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual axi_if)::get(this, "", "axi_vif", vif))
      `uvm_fatal("MON", "axi_if not found in config_db")
    mon_ap = new("mon_ap", this);
  endfunction

  task wait_for_reset_release();
    // Wait until reset is seen asserted at least once
    do @(vif.mon_cb); while (vif.mon_cb.ARESETn !== 1'b0);

    // Then wait until it is cleanly deasserted
    do @(vif.mon_cb); while (vif.mon_cb.ARESETn !== 1'b1);

    // Give one extra clean cycle before accepting first handshake
    @(vif.mon_cb);

    `uvm_info("MON_RST",
      $sformatf("Monitor armed after reset release at time=%0t", $time),
      UVM_MEDIUM)
  endtask

  task observe_writes();
    forever begin
      axi_item it;
      bit [3:0]  cap_id;
      bit [31:0] cap_addr;
      bit [7:0]  cap_len;
      bit [2:0]  cap_size;
      bit [1:0]  cap_burst;
      bit [31:0] cap_wdata[];
      bit [3:0]  cap_wstrb[];
      int        beats;
      bit        abort_txn;

      // Wait for AW handshake only when safely out of reset
      do @(vif.mon_cb);
      while (!(vif.mon_cb.ARESETn && vif.mon_cb.AWVALID && vif.mon_cb.AWREADY));

      cap_id    = vif.mon_cb.AWID;
      cap_addr  = vif.mon_cb.AWADDR;
      cap_len   = vif.mon_cb.AWLEN;
      cap_size  = vif.mon_cb.AWSIZE;
      cap_burst = vif.mon_cb.AWBURST;
      beats     = cap_len + 1;
      cap_wdata = new[beats];
      cap_wstrb = new[beats];
      abort_txn = 0;

      if (!first_obs_aw_printed) begin
        `uvm_info("MON_AW_FIRST",
          $sformatf("FIRST_OBS_AW id=%0h addr=0x%08h len=%0d size=%0d burst=%0b time=%0t",
                    cap_id, cap_addr, cap_len, cap_size, cap_burst, $time),
          UVM_MEDIUM)
        first_obs_aw_printed = 1;
      end else begin
        `uvm_info("MON_AW",
          $sformatf("OBS_AW id=%0h addr=0x%08h len=%0d size=%0d burst=%0b time=%0t",
                    cap_id, cap_addr, cap_len, cap_size, cap_burst, $time),
          UVM_HIGH)
      end

      // Collect W data beats
      for (int b = 0; b < beats; b++) begin
        do @(vif.mon_cb);
        while (!(vif.mon_cb.WVALID && vif.mon_cb.WREADY) && vif.mon_cb.ARESETn);

        if (!vif.mon_cb.ARESETn) begin
          `uvm_warning("MON_WR_ABORT",
            $sformatf("Reset hit during W capture, aborting partial write txn at time=%0t", $time))
          abort_txn = 1;
          break;
        end

        cap_wdata[b] = vif.mon_cb.WDATA;
        cap_wstrb[b] = vif.mon_cb.WSTRB;

        `uvm_info("MON_W",
          $sformatf("OBS_W beat=%0d data=0x%08h strb=0x%0h last=%0b time=%0t",
                    b, cap_wdata[b], cap_wstrb[b], vif.mon_cb.WLAST, $time),
          UVM_HIGH)
      end

      if (abort_txn)
        continue;

      // Collect B response
      do @(vif.mon_cb);
      while (!(vif.mon_cb.BVALID && vif.mon_cb.BREADY) && vif.mon_cb.ARESETn);

      if (!vif.mon_cb.ARESETn) begin
        `uvm_warning("MON_B_ABORT",
          $sformatf("Reset hit while waiting for B, aborting partial write txn at time=%0t", $time))
        continue;
      end

      it           = axi_item::type_id::create("mon_wr");
      it.do_reset  = 0;
      it.is_write  = 1;
      it.id        = cap_id;
      it.addr      = cap_addr;
      it.len       = cap_len;
      it.size      = axsize_e'(cap_size);
      it.raw_burst = cap_burst;
      it.wdata     = cap_wdata;
      it.wstrb     = cap_wstrb;
      it.bresp     = vif.mon_cb.BRESP;

      mon_ap.write(it);
    end
  endtask

  task observe_reads();
    forever begin
      axi_item it;
      bit [3:0]  cap_id;
      bit [31:0] cap_addr;
      bit [7:0]  cap_len;
      bit [2:0]  cap_size;
      bit [1:0]  cap_burst;
      bit [31:0] cap_rdata[];
      bit [1:0]  cap_rresp[];
      int        beats;
      bit        abort_txn;

      do @(vif.mon_cb);
      while (!(vif.mon_cb.ARESETn && vif.mon_cb.ARVALID && vif.mon_cb.ARREADY));

      cap_id    = vif.mon_cb.ARID;
      cap_addr  = vif.mon_cb.ARADDR;
      cap_len   = vif.mon_cb.ARLEN;
      cap_size  = vif.mon_cb.ARSIZE;
      cap_burst = vif.mon_cb.ARBURST;
      beats     = cap_len + 1;
      cap_rdata = new[beats];
      cap_rresp = new[beats];
      abort_txn = 0;

      if (!first_obs_ar_printed) begin
        `uvm_info("MON_AR_FIRST",
          $sformatf("FIRST_OBS_AR id=%0h addr=0x%08h len=%0d size=%0d burst=%0b time=%0t",
                    cap_id, cap_addr, cap_len, cap_size, cap_burst, $time),
          UVM_MEDIUM)
        first_obs_ar_printed = 1;
      end else begin
        `uvm_info("MON_AR",
          $sformatf("OBS_AR id=%0h addr=0x%08h len=%0d size=%0d burst=%0b time=%0t",
                    cap_id, cap_addr, cap_len, cap_size, cap_burst, $time),
          UVM_HIGH)
      end

      // Collect R data beats
      for (int b = 0; b < beats; b++) begin
        do @(vif.mon_cb);
        while (!(vif.mon_cb.RVALID && vif.mon_cb.RREADY) && vif.mon_cb.ARESETn);

        if (!vif.mon_cb.ARESETn) begin
          `uvm_warning("MON_RD_ABORT",
            $sformatf("Reset hit during R capture, aborting partial read txn at time=%0t", $time))
          abort_txn = 1;
          break;
        end

        cap_rdata[b] = vif.mon_cb.RDATA;
        cap_rresp[b] = vif.mon_cb.RRESP;

        `uvm_info("MON_R",
          $sformatf("OBS_R beat=%0d data=0x%08h resp=%0b last=%0b time=%0t",
                    b, cap_rdata[b], cap_rresp[b], vif.mon_cb.RLAST, $time),
          UVM_HIGH)
      end

      if (abort_txn)
        continue;

      it           = axi_item::type_id::create("mon_rd");
      it.do_reset  = 0;
      it.is_write  = 0;
      it.id        = cap_id;
      it.addr      = cap_addr;
      it.len       = cap_len;
      it.size      = axsize_e'(cap_size);
      it.raw_burst = cap_burst;
      it.rdata     = cap_rdata;
      it.rresp     = cap_rresp;

      mon_ap.write(it);
    end
  endtask

  virtual task run_phase(uvm_phase phase);
    wait_for_reset_release();
    fork
      observe_writes();
      observe_reads();
    join
  endtask
endclass


// =============================================================================
// Scoreboard
// =============================================================================
class axi_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(axi_scoreboard)

  uvm_analysis_imp #(axi_item, axi_scoreboard) sb_imp;

  logic [7:0] ref_mem [1024];
  int pass_cnt, fail_cnt;

  function new(string name = "axi_scoreboard", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sb_imp = new("sb_imp", this);
    foreach (ref_mem[i]) ref_mem[i] = 8'h00;
    pass_cnt = 0;
    fail_cnt = 0;
  endfunction

  function automatic bit size_supported_f(input logic [2:0] sz);
    return (sz == AXI_SIZE_1B) || (sz == AXI_SIZE_2B) || (sz == AXI_SIZE_4B);
  endfunction

  function automatic bit burst_supported_f(input logic [1:0] burst);
    return (burst != AXI_BURST_RSVD);
  endfunction

  function automatic bit wrap_len_ok_f(input logic [7:0] len);
    int beats;
    begin
      beats = len + 1;
      return ((beats == 2) || (beats == 4) || (beats == 8) || (beats == 16));
    end
  endfunction

  function automatic bit wrap_align_ok_f(
    input logic [31:0] addr,
    input logic [2:0]  size
  );
    logic [31:0] mask;
    begin
      mask = (32'd1 << size) - 1;
      return ((addr & mask) == 0);
    end
  endfunction

  function automatic bit req_ok_f(
    input logic [31:0] addr,
    input logic [2:0]  size,
    input logic [7:0]  len,
    input logic [1:0]  burst
  );
    return size_supported_f(size) &&
           burst_supported_f(burst) &&
           ((burst != AXI_BURST_WRAP) || (wrap_len_ok_f(len) && wrap_align_ok_f(addr, size)));
  endfunction

  function automatic logic [31:0] next_addr_ref(
    input logic [31:0] cur_addr,
    input logic [31:0] start_addr,
    input logic [2:0]  axsize,
    input logic [1:0]  axburst,
    input logic [7:0]  axlen,
    input logic [7:0]  beat_idx
  );
    logic [31:0] size_bytes;
    logic [31:0] aligned_addr;
    logic [31:0] container_bytes;
    logic [31:0] wrap_boundary;
    logic [31:0] upper_wrap_boundary;
    logic [31:0] nxt;
    logic [31:0] size_mask;
    begin
      size_bytes          = (32'd1 << axsize);
      size_mask           = size_bytes - 1;
      aligned_addr        = start_addr & ~size_mask;
      container_bytes     = size_bytes * (axlen + 1);
      wrap_boundary       = start_addr - (start_addr % container_bytes);
      upper_wrap_boundary = wrap_boundary + container_bytes;

      case (axburst)
        AXI_BURST_FIXED: nxt = cur_addr;

        AXI_BURST_WRAP: begin
          if ((beat_idx == 0) && ((start_addr & size_mask) != 0))
            nxt = aligned_addr + size_bytes;
          else
            nxt = cur_addr + size_bytes;

          if (nxt >= upper_wrap_boundary)
            nxt = wrap_boundary;
        end

        default: begin
          if ((beat_idx == 0) && ((start_addr & size_mask) != 0))
            nxt = aligned_addr + size_bytes;
          else
            nxt = cur_addr + size_bytes;
        end
      endcase

      return nxt;
    end
  endfunction

  function automatic logic [7:0] ref_read_byte(input int unsigned byte_addr);
    if (byte_addr < 1024) ref_read_byte = ref_mem[byte_addr];
    else                  ref_read_byte = 8'h00;
  endfunction

  function automatic logic [31:0] build_exp_rdata(
    input logic [31:0] cur_addr,
    input logic [2:0]  axsize
  );
    logic [31:0] data;
    logic [31:0] size_bytes;
    logic [31:0] aligned_addr;
    logic [31:0] size_mask;
    bit          aligned;
    int unsigned lower_lane;
    int unsigned upper_lane;
    int unsigned lane;
    int unsigned src_byte;
    begin
      data         = '0;
      size_bytes   = (32'd1 << axsize);
      size_mask    = size_bytes - 1;
      aligned      = ((cur_addr & size_mask) == 0);
      aligned_addr = cur_addr & ~size_mask;

      lower_lane = cur_addr % 4;
      if (aligned)
        upper_lane = lower_lane + size_bytes - 1;
      else
        upper_lane = (aligned_addr + size_bytes - 1) % 4;

      src_byte = 0;
      for (lane = lower_lane; lane <= upper_lane; lane++) begin
        data[8*lane +: 8] = ref_read_byte(cur_addr + src_byte);
        src_byte++;
      end
      return data;
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

  virtual function void write(axi_item it);
    logic [31:0] addr, base;
    int beats;

    beats = it.len + 1;
    addr  = it.addr;
    base  = it.addr;

    if (it.is_write) begin
      if (!req_ok_f(it.addr, it.size, it.len, it.raw_burst)) begin
        chk($sformatf("WR SLVERR [size=%0d burst=%0b addr=0x%08h]",
                      it.size, it.raw_burst, it.addr),
            it.bresp == AXI_RESP_SLVERR);
        return;
      end

      chk($sformatf("WR OKAY [addr=0x%08h len=%0d size=%0d burst=%0b]",
                    it.addr, it.len, it.size, it.raw_burst),
          it.bresp == AXI_RESP_OKAY);

      for (int b = 0; b < beats; b++) begin
        int unsigned word_base;
        word_base = {addr[31:2], 2'b00};

        for (int byte_idx = 0; byte_idx < 4; byte_idx++) begin
          if (it.wstrb[b][byte_idx]) begin
            int unsigned mem_byte_addr;
            mem_byte_addr = word_base + byte_idx;
            if (mem_byte_addr < 1024)
              ref_mem[mem_byte_addr] = it.wdata[b][byte_idx*8 +: 8];
          end
        end

        addr = next_addr_ref(addr, base, it.size, it.raw_burst, it.len, b);
      end

    end else begin
      for (int b = 0; b < beats; b++) begin
        if (!req_ok_f(it.addr, it.size, it.len, it.raw_burst)) begin
          chk($sformatf("RD SLVERR [size=%0d burst=%0b addr=0x%08h beat=%0d]",
                        it.size, it.raw_burst, it.addr, b),
              it.rresp[b] == AXI_RESP_SLVERR);
        end else begin
          logic [31:0] exp_rdata;

          chk($sformatf("RD OKAY [addr=0x%08h beat=%0d]", addr, b),
              it.rresp[b] == AXI_RESP_OKAY);

          exp_rdata = build_exp_rdata(addr, it.size);

          chk($sformatf("RD DATA [addr=0x%08h beat=%0d exp=0x%08h got=0x%08h]",
                        addr, b, exp_rdata, it.rdata[b]),
              it.rdata[b] === exp_rdata);
        end

        addr = next_addr_ref(addr, base, it.size, it.raw_burst, it.len, b);
      end
    end
  endfunction

  virtual function void report_phase(uvm_phase phase);
    `uvm_info("SB",
      $sformatf("=== Scoreboard: %0d PASS  %0d FAIL ===", pass_cnt, fail_cnt),
      UVM_NONE)
  endfunction
endclass


// =============================================================================
// Functional Coverage
// =============================================================================
class axi_func_cov extends uvm_subscriber #(axi_item);
  `uvm_component_utils(axi_func_cov)

  typedef axi_item T;
  T f_item;

  covergroup cg_channels;
    option.per_instance = 1;
    cp_dir : coverpoint f_item.is_write { bins WRITE = {1}; bins READ = {0}; }
    cp_size : coverpoint f_item.size {
      bins BYTE  = {AXI_SIZE_1B};
      bins HALF  = {AXI_SIZE_2B};
      bins WORD  = {AXI_SIZE_4B};
      bins UNSUP = {AXI_SIZE_8B, AXI_SIZE_16B};
    }
    cp_len : coverpoint f_item.len {
      bins SINGLE  = {8'h00};
      bins LEN_2_4 = {[8'h01:8'h03]};
      bins LEN_5_8 = {[8'h04:8'h07]};
      bins LEN_GE9 = {[8'h08:8'hFF]};
    }
  endgroup

  covergroup cg_responses;
    option.per_instance = 1;
    cp_bresp : coverpoint f_item.bresp {
      bins OKAY   = {AXI_RESP_OKAY};
      bins SLVERR = {AXI_RESP_SLVERR};
    }
    cp_dir : coverpoint f_item.is_write { bins WRITE = {1}; bins READ = {0}; }
    cx_resp_dir : cross cp_bresp, cp_dir;
  endgroup

  covergroup cg_transactions;
    option.per_instance = 1;
    cp_dir : coverpoint f_item.is_write { bins WRITE = {1}; bins READ = {0}; }
    cp_size : coverpoint f_item.size {
      bins BYTE  = {AXI_SIZE_1B};
      bins HALF  = {AXI_SIZE_2B};
      bins WORD  = {AXI_SIZE_4B};
      bins UNSUP = {AXI_SIZE_8B, AXI_SIZE_16B};
    }
    cx_dir_size : cross cp_dir, cp_size;
  endgroup

  covergroup cg_byte_lanes;
    option.per_instance = 1;
    cp_addr_lo : coverpoint f_item.addr[1:0] {
      bins BYTE0 = {2'b00};
      bins BYTE1 = {2'b01};
      bins BYTE2 = {2'b10};
      bins BYTE3 = {2'b11};
    }
    cp_size : coverpoint f_item.size {
      bins BYTE = {AXI_SIZE_1B};
      bins HALF = {AXI_SIZE_2B};
      bins WORD = {AXI_SIZE_4B};
    }
    cx_size_lane : cross cp_size, cp_addr_lo;
  endgroup

  covergroup cg_protocol_errors;
    option.per_instance = 1;
    cp_raw_burst : coverpoint f_item.raw_burst {
      bins FIXED    = {2'b00};
      bins INCR     = {2'b01};
      bins WRAP     = {2'b10};
      bins RESERVED = {2'b11};
    }
    cp_size : coverpoint f_item.size {
      bins BYTE = {AXI_SIZE_1B};
      bins HALF = {AXI_SIZE_2B};
      bins WORD = {AXI_SIZE_4B};
      bins UNSUP = {AXI_SIZE_8B, AXI_SIZE_16B};
    }
    cp_addr_lo : coverpoint f_item.addr[1:0] {
      bins B0 = {2'b00};
      bins B1 = {2'b01};
      bins B2 = {2'b10};
      bins B3 = {2'b11};
    }
  endgroup

  function new(string name = "axi_func_cov", uvm_component parent = null);
    super.new(name, parent);
    f_item             = axi_item::type_id::create("f_item");
    cg_channels        = new();
    cg_responses       = new();
    cg_transactions    = new();
    cg_byte_lanes      = new();
    cg_protocol_errors = new();
  endfunction

  virtual function void write(T t);
    void'(f_item.copy(t));
    cg_channels.sample();
    cg_responses.sample();
    cg_transactions.sample();
    cg_byte_lanes.sample();
    cg_protocol_errors.sample();
  endfunction

  virtual function void report_phase(uvm_phase phase);
    `uvm_info("FC", $sformatf("Coverage channels:        %0.2f%%", cg_channels.get_inst_coverage()), UVM_NONE)
    `uvm_info("FC", $sformatf("Coverage responses:       %0.2f%%", cg_responses.get_inst_coverage()), UVM_NONE)
    `uvm_info("FC", $sformatf("Coverage transactions:    %0.2f%%", cg_transactions.get_inst_coverage()), UVM_NONE)
    `uvm_info("FC", $sformatf("Coverage byte lanes:      %0.2f%%", cg_byte_lanes.get_inst_coverage()), UVM_NONE)
    `uvm_info("FC", $sformatf("Coverage protocol errors: %0.2f%%", cg_protocol_errors.get_inst_coverage()), UVM_NONE)
  endfunction
endclass


// =============================================================================
// Agent / Env
// =============================================================================
class axi_agent extends uvm_agent;
  `uvm_component_utils(axi_agent)

  axi_monitor               mon;
  axi_driver                drv;
  uvm_sequencer #(axi_item) seqr;

  function new(string name = "axi_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon  = axi_monitor::type_id::create("mon", this);
    drv  = axi_driver::type_id::create("drv", this);
    seqr = uvm_sequencer #(axi_item)::type_id::create("seqr", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(seqr.seq_item_export);
  endfunction
endclass


class axi_env extends uvm_env;
  `uvm_component_utils(axi_env)

  axi_agent      agt;
  axi_scoreboard sb;
  axi_func_cov   fc;

  function new(string name = "axi_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agt = axi_agent::type_id::create("agt", this);
    sb  = axi_scoreboard::type_id::create("sb", this);
    fc  = axi_func_cov::type_id::create("fc", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agt.mon.mon_ap.connect(sb.sb_imp);
    agt.mon.mon_ap.connect(fc.analysis_export);
  endfunction
endclass


// =============================================================================
// Tests
// =============================================================================
class axi_base_test extends uvm_test;
  `uvm_component_utils(axi_base_test)

  axi_env        env;
  virtual axi_if vif;
  axi_base_seq   seq;

  function new(string name = "axi_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual axi_if)::get(this, "", "axi_vif", vif))
      `uvm_fatal("TEST", "axi_if not found in config_db")
    uvm_config_db #(virtual axi_if)::set(this, "env.agt.*", "axi_vif", vif);
    env = axi_env::type_id::create("env", this);
    seq = axi_base_seq::type_id::create("seq");
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    void'(seq.randomize());
    seq.start(env.agt.seqr);
    phase.drop_objection(this);
  endtask
endclass


class test_single_wr_rd extends axi_base_test;
  `uvm_component_utils(test_single_wr_rd)
  function new(string name = "test_single_wr_rd", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  virtual function void build_phase(uvm_phase phase);
    axi_base_seq::type_id::set_type_override(seq_single_wr_rd::get_type());
    super.build_phase(phase);
  endfunction
endclass


class test_incr4_burst extends axi_base_test;
  `uvm_component_utils(test_incr4_burst)
  function new(string name = "test_incr4_burst", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  virtual function void build_phase(uvm_phase phase);
    axi_base_seq::type_id::set_type_override(seq_incr4_burst::get_type());
    super.build_phase(phase);
  endfunction
endclass


class test_narrow_xfer extends axi_base_test;
  `uvm_component_utils(test_narrow_xfer)
  function new(string name = "test_narrow_xfer", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  virtual function void build_phase(uvm_phase phase);
    axi_base_seq::type_id::set_type_override(seq_narrow_xfer::get_type());
    super.build_phase(phase);
  endfunction
endclass


class test_size_error extends axi_base_test;
  `uvm_component_utils(test_size_error)
  function new(string name = "test_size_error", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  virtual function void build_phase(uvm_phase phase);
    axi_base_seq::type_id::set_type_override(seq_size_error::get_type());
    super.build_phase(phase);
  endfunction
endclass


class test_narrow_read_lanes extends axi_base_test;
  `uvm_component_utils(test_narrow_read_lanes)
  function new(string name = "test_narrow_read_lanes", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  virtual function void build_phase(uvm_phase phase);
    axi_base_seq::type_id::set_type_override(seq_narrow_read_lanes::get_type());
    super.build_phase(phase);
  endfunction
endclass


class test_illegal_wrap_len extends axi_base_test;
  `uvm_component_utils(test_illegal_wrap_len)
  function new(string name = "test_illegal_wrap_len", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  virtual function void build_phase(uvm_phase phase);
    axi_base_seq::type_id::set_type_override(seq_illegal_wrap_len::get_type());
    super.build_phase(phase);
  endfunction
endclass


class test_illegal_wrap_align extends axi_base_test;
  `uvm_component_utils(test_illegal_wrap_align)
  function new(string name = "test_illegal_wrap_align", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  virtual function void build_phase(uvm_phase phase);
    axi_base_seq::type_id::set_type_override(seq_illegal_wrap_align::get_type());
    super.build_phase(phase);
  endfunction
endclass


class test_reserved_burst extends axi_base_test;
  `uvm_component_utils(test_reserved_burst)
  function new(string name = "test_reserved_burst", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  virtual function void build_phase(uvm_phase phase);
    axi_base_seq::type_id::set_type_override(seq_reserved_burst::get_type());
    super.build_phase(phase);
  endfunction
endclass

class axi_driver_backpressure extends axi_driver;
  `uvm_component_utils(axi_driver_backpressure)
 
  // Configuration knobs for back-pressure behavior
  rand int unsigned bp_aw_delay;    // Cycles to delay AWREADY
  rand int unsigned bp_w_delay;     // Cycles to delay WREADY
  rand int unsigned bp_ar_delay;    // Cycles to delay ARREADY
  rand int unsigned bp_b_cycles;    // Cycles to hold BREADY=0
  rand int unsigned bp_r_cycles;    // Cycles to hold RREADY=0
  
  bit enable_aw_backpressure = 0;
  bit enable_w_backpressure  = 0;
  bit enable_ar_backpressure = 0;
  bit enable_b_backpressure  = 0;
  bit enable_r_backpressure  = 0;
 
  constraint c_bp_delays {
    bp_aw_delay inside {[1:3]};
    bp_w_delay  inside {[1:3]};
    bp_ar_delay inside {[1:3]};
    bp_b_cycles inside {[1:3]};
    bp_r_cycles inside {[1:3]};
  }
 
  function new(string name = "axi_driver_backpressure", uvm_component parent = null);
    super.new(name, parent);
  endfunction
 
  // Override idle_all to support back-pressure modes
  virtual task idle_all();
    vif.drv_cb.ARESETn <= 1'b1;
 
    vif.drv_cb.AWVALID <= 1'b0;
    vif.drv_cb.AWID    <= '0;
    vif.drv_cb.AWADDR  <= '0;
    vif.drv_cb.AWLEN   <= '0;
    vif.drv_cb.AWSIZE  <= AXI_SIZE_4B;
    vif.drv_cb.AWBURST <= AXI_BURST_INCR;
 
    vif.drv_cb.WVALID  <= 1'b0;
    vif.drv_cb.WDATA   <= '0;
    vif.drv_cb.WSTRB   <= '0;
    vif.drv_cb.WLAST   <= 1'b0;
 
    // BREADY defaults to 1, but can be controlled for back-pressure
    vif.drv_cb.BREADY  <= 1'b1;
 
    vif.drv_cb.ARVALID <= 1'b0;
    vif.drv_cb.ARID    <= '0;
    vif.drv_cb.ARADDR  <= '0;
    vif.drv_cb.ARLEN   <= '0;
    vif.drv_cb.ARSIZE  <= AXI_SIZE_4B;
    vif.drv_cb.ARBURST <= AXI_BURST_INCR;
 
    // RREADY defaults to 1, but can be controlled for back-pressure
    vif.drv_cb.RREADY  <= 1'b1;
  endtask
 
  // Override drive_write to support AW and W back-pressure
  virtual task drive_write(axi_item it);
    int beats = it.len + 1;
 
    // =========================================================================
    // AW CHANNEL with optional back-pressure
    // =========================================================================
    @(vif.drv_cb);
    vif.drv_cb.AWVALID <= 1'b1;
    vif.drv_cb.AWID    <= it.id;
    vif.drv_cb.AWADDR  <= it.addr;
    vif.drv_cb.AWLEN   <= it.len;
    vif.drv_cb.AWSIZE  <= it.size;
    vif.drv_cb.AWBURST <= it.raw_burst;
 
    if (enable_aw_backpressure) begin
      `uvm_info("BP_DRV", $sformatf("AW backpressure: AWVALID asserted, waiting %0d cycles before AWREADY", bp_aw_delay), UVM_MEDIUM)
      
      // Wait specified delay cycles - AWVALID must remain stable
      repeat(bp_aw_delay) begin
        @(vif.drv_cb);
        if (!vif.drv_cb.AWREADY) begin
          // AWVALID and payload must stay stable - this triggers the assertions
        end
      end
    end
 
    // Now wait for actual handshake
    do @(vif.drv_cb); while (!vif.drv_cb.AWREADY);
    vif.drv_cb.AWVALID <= 1'b0;
 
    // =========================================================================
    // W CHANNEL with optional back-pressure
    // =========================================================================
    for (int b = 0; b < beats; b++) begin
      vif.drv_cb.WVALID <= 1'b1;
      vif.drv_cb.WDATA  <= it.wdata[b];
      vif.drv_cb.WSTRB  <= it.wstrb[b];
      vif.drv_cb.WLAST  <= (b == beats-1);
 
      if (enable_w_backpressure && (b == 0)) begin
        `uvm_info("BP_DRV", $sformatf("W backpressure: WVALID asserted, waiting %0d cycles before WREADY", bp_w_delay), UVM_MEDIUM)
        
        // Wait specified delay cycles - WVALID and payload must remain stable
        repeat(bp_w_delay) begin
          @(vif.drv_cb);
          if (!vif.drv_cb.WREADY) begin
            // WVALID and W payload must stay stable - triggers assertions
          end
        end
      end
 
      do @(vif.drv_cb); while (!vif.drv_cb.WREADY);
    end
 
    vif.drv_cb.WVALID <= 1'b0;
    vif.drv_cb.WLAST  <= 1'b0;
 
    // =========================================================================
    // B CHANNEL with optional back-pressure
    // FIX: Don't sample BREADY - just control it and track state locally
    // =========================================================================
    if (enable_b_backpressure) begin
      // Deassert BREADY to create back-pressure on B channel
      vif.drv_cb.BREADY <= 1'b0;
      `uvm_info("BP_DRV", $sformatf("B backpressure: BREADY=0 for %0d cycles", bp_b_cycles), UVM_MEDIUM)
      
      // Wait for BVALID to be asserted
      do @(vif.drv_cb); while (!vif.drv_cb.BVALID);
      
      // Keep BREADY low for specified cycles - BVALID must remain stable
      // FIX: Just wait the cycles, don't check BREADY (it's an output)
      repeat(bp_b_cycles) @(vif.drv_cb);
      
      // Now assert BREADY to complete handshake
      vif.drv_cb.BREADY <= 1'b1;
      
      // Wait for handshake to complete
      do @(vif.drv_cb); while (!vif.drv_cb.BVALID);
    end else begin
      // Normal operation - BREADY already 1, wait for BVALID
      do @(vif.drv_cb); while (!vif.drv_cb.BVALID);
    end
  endtask
 
  // Override drive_read to support AR and R back-pressure
  virtual task drive_read(axi_item it);
    int beats = it.len + 1;
 
    // =========================================================================
    // AR CHANNEL with optional back-pressure
    // =========================================================================
    @(vif.drv_cb);
    vif.drv_cb.ARVALID <= 1'b1;
    vif.drv_cb.ARID    <= it.id;
    vif.drv_cb.ARADDR  <= it.addr;
    vif.drv_cb.ARLEN   <= it.len;
    vif.drv_cb.ARSIZE  <= it.size;
    vif.drv_cb.ARBURST <= it.raw_burst;
 
    if (enable_ar_backpressure) begin
      `uvm_info("BP_DRV", $sformatf("AR backpressure: ARVALID asserted, waiting %0d cycles before ARREADY", bp_ar_delay), UVM_MEDIUM)
      
      // Wait specified delay cycles - ARVALID and payload must remain stable
      repeat(bp_ar_delay) begin
        @(vif.drv_cb);
        if (!vif.drv_cb.ARREADY) begin
          // ARVALID and payload must stay stable - triggers assertions
        end
      end
    end
 
    // Now wait for actual handshake
    do @(vif.drv_cb); while (!vif.drv_cb.ARREADY);
    vif.drv_cb.ARVALID <= 1'b0;
 
    // =========================================================================
    // R CHANNEL with optional back-pressure
    // FIX: Don't sample RREADY - just control it and track state locally
    // =========================================================================
    if (enable_r_backpressure) begin
      for (int b = 0; b < beats; b++) begin
        // Deassert RREADY to create back-pressure
        vif.drv_cb.RREADY <= 1'b0;
        `uvm_info("BP_DRV", $sformatf("R backpressure beat %0d: RREADY=0 for %0d cycles", b, bp_r_cycles), UVM_MEDIUM)
        
        // Wait for RVALID to be asserted
        do @(vif.drv_cb); while (!vif.drv_cb.RVALID);
        
        // Keep RREADY low for specified cycles - RVALID must remain stable
        // FIX: Just wait the cycles, don't check RREADY (it's an output)
        repeat(bp_r_cycles) @(vif.drv_cb);
        
        // Now assert RREADY to complete handshake
        vif.drv_cb.RREADY <= 1'b1;
        
        // Wait for handshake to complete
        do @(vif.drv_cb); while (!vif.drv_cb.RVALID);
      end
    end else begin
      // Normal operation - RREADY already 1, wait for all R beats
      for (int b = 0; b < beats; b++) begin
        do @(vif.drv_cb); while (!vif.drv_cb.RVALID);
      end
    end
  endtask
 
endclass
 
 
// =============================================================================
// SEQUENCE 1: AW Channel Back-pressure
// Targets: ASSERT_AWVALID_STABLE, ASSERT_AW_PAYLOAD_STABLE
// =============================================================================
 
class seq_aw_backpressure extends axi_base_seq;
  `uvm_object_utils(seq_aw_backpressure)
  constraint c_num_ovr { num_txns == 5; }
 
  function new(string name = "seq_aw_backpressure");
    super.new(name);
  endfunction
 
  virtual task body();
    send_reset();
 
    repeat (num_txns) begin
      axi_item it = axi_item::type_id::create("aw_bp_txn");
      start_item(it);
      if (!it.randomize() with { 
        do_reset == 0; 
        is_write == 1;
        len == 0;  // Single beat for simplicity
      })
        `uvm_fatal("SEQ", "Randomization failed")
      finish_item(it);
    end
  endtask
endclass
 
 
// =============================================================================
// SEQUENCE 2: W Channel Back-pressure
// Targets: ASSERT_WVALID_STABLE, ASSERT_W_PAYLOAD_STABLE
// =============================================================================
 
class seq_w_backpressure extends axi_base_seq;
  `uvm_object_utils(seq_w_backpressure)
  constraint c_num_ovr { num_txns == 5; }
 
  function new(string name = "seq_w_backpressure");
    super.new(name);
  endfunction
 
  virtual task body();
    send_reset();
 
    repeat (num_txns) begin
      axi_item it = axi_item::type_id::create("w_bp_txn");
      start_item(it);
      if (!it.randomize() with { 
        do_reset == 0; 
        is_write == 1;
        len inside {[0:3]};  // 1-4 beats
      })
        `uvm_fatal("SEQ", "Randomization failed")
      finish_item(it);
    end
  endtask
endclass
 
 
// =============================================================================
// SEQUENCE 3: B Channel Back-pressure
// Targets: ASSERT_BVALID_STABLE
// =============================================================================
 
class seq_b_backpressure extends axi_base_seq;
  `uvm_object_utils(seq_b_backpressure)
  constraint c_num_ovr { num_txns == 5; }
 
  function new(string name = "seq_b_backpressure");
    super.new(name);
  endfunction
 
  virtual task body();
    send_reset();
 
    repeat (num_txns) begin
      axi_item it = axi_item::type_id::create("b_bp_txn");
      start_item(it);
      if (!it.randomize() with { 
        do_reset == 0; 
        is_write == 1;
        len == 0;
      })
        `uvm_fatal("SEQ", "Randomization failed")
      finish_item(it);
    end
  endtask
endclass
 
 
// =============================================================================
// SEQUENCE 4: AR Channel Back-pressure
// Targets: ASSERT_ARVALID_STABLE, ASSERT_AR_PAYLOAD_STABLE
// =============================================================================
 
class seq_ar_backpressure extends axi_base_seq;
  `uvm_object_utils(seq_ar_backpressure)
  constraint c_num_ovr { num_txns == 5; }
 
  function new(string name = "seq_ar_backpressure");
    super.new(name);
  endfunction
 
  virtual task body();
    send_reset();
 
    repeat (num_txns) begin
      axi_item it = axi_item::type_id::create("ar_bp_txn");
      start_item(it);
      if (!it.randomize() with { 
        do_reset == 0; 
        is_write == 0;  // READ
        len == 0;
      })
        `uvm_fatal("SEQ", "Randomization failed")
      finish_item(it);
    end
  endtask
endclass
 
 
// =============================================================================
// SEQUENCE 5: R Channel Back-pressure
// Targets: ASSERT_RVALID_STABLE
// =============================================================================
 
class seq_r_backpressure extends axi_base_seq;
  `uvm_object_utils(seq_r_backpressure)
  constraint c_num_ovr { num_txns == 5; }
 
  function new(string name = "seq_r_backpressure");
    super.new(name);
  endfunction
 
  virtual task body();
    send_reset();
 
    repeat (num_txns) begin
      axi_item it = axi_item::type_id::create("r_bp_txn");
      start_item(it);
      if (!it.randomize() with { 
        do_reset == 0; 
        is_write == 0;  // READ
        len inside {[0:3]};  // 1-4 beats
      })
        `uvm_fatal("SEQ", "Randomization failed")
      finish_item(it);
    end
  endtask
endclass
 
 
// =============================================================================
// SEQUENCE 6: Comprehensive Back-pressure (All channels)
// Targets: ALL 8 stability assertions
// =============================================================================
 
class seq_comprehensive_backpressure extends axi_base_seq;
  `uvm_object_utils(seq_comprehensive_backpressure)
  constraint c_num_ovr { num_txns == 10; }
 
  function new(string name = "seq_comprehensive_backpressure");
    super.new(name);
  endfunction
 
  virtual task body();
    send_reset();
 
    repeat (num_txns) begin
      axi_item it = axi_item::type_id::create("comprehensive_bp");
      start_item(it);
      if (!it.randomize() with { 
        do_reset == 0; 
        len inside {[0:4]};
      })
        `uvm_fatal("SEQ", "Randomization failed")
      finish_item(it);
    end
  endtask
endclass
 
 
// =============================================================================
// SEQUENCE 7: Medium Burst Length (len=4-7)
// Targets: cp_len LEN_5_8 bin
// =============================================================================
 
class seq_medium_burst extends axi_base_seq;
  `uvm_object_utils(seq_medium_burst)
  constraint c_num_ovr { num_txns == 8; }
 
  function new(string name = "seq_medium_burst");
    super.new(name);
  endfunction
 
  virtual task body();
    send_reset();
 
    repeat (num_txns) begin
      bit [31:0] base_addr;
      bit [7:0]  burst_len;
      bit        is_wr;
      
      base_addr  = ($urandom_range(0, 240)) * 4;
      burst_len  = $urandom_range(4, 7);  // len=4,5,6,7 → 5-8 beats
      is_wr      = $urandom_range(0, 1);
 
      begin
        axi_item it = axi_item::type_id::create("medium_burst");
        start_item(it);
        it.do_reset  = 0;
        it.is_write  = is_wr;
        it.id        = $urandom_range(0, 15);
        it.addr      = base_addr;
        it.len       = burst_len;
        it.size      = AXI_SIZE_4B;
        it.raw_burst = AXI_BURST_INCR;
        it.wdata     = new[burst_len + 1];
        it.wstrb     = new[burst_len + 1];
        foreach (it.wdata[i]) begin
          it.wdata[i] = $urandom();
          it.wstrb[i] = 4'hF;
        end
        finish_item(it);
        
        `uvm_info("SEQ_MED_BURST", 
          $sformatf("Medium burst: %s len=%0d addr=0x%08h", 
                    is_wr ? "WRITE" : "READ", burst_len, base_addr), 
          UVM_MEDIUM)
      end
    end
  endtask
endclass
 
 
// =============================================================================
// SEQUENCE 8: Read Error Scenarios
// Targets: SLVERR × READ cross coverage
// =============================================================================
 
class seq_read_errors extends axi_base_seq;
  `uvm_object_utils(seq_read_errors)
  constraint c_num_ovr { num_txns == 12; }
 
  function new(string name = "seq_read_errors");
    super.new(name);
  endfunction
 
  virtual task body();
    send_reset();
 
    // Test 1: Unsupported size on reads
    repeat (4) begin
      axi_item it = axi_item::type_id::create("rd_err_size");
      start_item(it);
      it.do_reset  = 0;
      it.is_write  = 0;  // READ
      it.id        = $urandom_range(0, 15);
      it.addr      = ($urandom_range(0, 255)) * 4;
      it.len       = 0;
      it.size      = AXI_SIZE_8B;  // Unsupported
      it.raw_burst = AXI_BURST_INCR;
      it.wdata     = new[1]; it.wdata[0] = '0;
      it.wstrb     = new[1]; it.wstrb[0] = '0;
      finish_item(it);
      
      `uvm_info("SEQ_RD_ERR", "Read with unsupported size=8B → expect SLVERR", UVM_MEDIUM)
    end
 
    // Test 2: Illegal WRAP burst on reads (bad length)
    repeat (4) begin
      axi_item it = axi_item::type_id::create("rd_err_wrap_len");
      start_item(it);
      it.do_reset  = 0;
      it.is_write  = 0;  // READ
      it.id        = $urandom_range(0, 15);
      it.addr      = 32'h0000_0080;  // Aligned
      it.len       = 8'h05;          // 6 beats - illegal for WRAP
      it.size      = AXI_SIZE_4B;
      it.raw_burst = AXI_BURST_WRAP;
      it.wdata     = new[6];
      it.wstrb     = new[6];
      foreach (it.wdata[i]) begin
        it.wdata[i] = '0;
        it.wstrb[i] = '0;
      end
      finish_item(it);
      
      `uvm_info("SEQ_RD_ERR", "Read WRAP with illegal len=5 → expect SLVERR", UVM_MEDIUM)
    end
 
    // Test 3: Reserved burst type on reads
    repeat (4) begin
      axi_item it = axi_item::type_id::create("rd_err_rsvd");
      start_item(it);
      it.do_reset  = 0;
      it.is_write  = 0;  // READ
      it.id        = $urandom_range(0, 15);
      it.addr      = ($urandom_range(0, 255)) * 4;
      it.len       = 0;
      it.size      = AXI_SIZE_4B;
      it.raw_burst = AXI_BURST_RSVD;  // Reserved
      it.wdata     = new[1]; it.wdata[0] = '0;
      it.wstrb     = new[1]; it.wstrb[0] = '0;
      finish_item(it);
      
      `uvm_info("SEQ_RD_ERR", "Read with reserved burst → expect SLVERR", UVM_MEDIUM)
    end
  endtask
endclass
 
 
// =============================================================================
// SEQUENCE 9: WORD × BYTE3 Coverage
// Targets: cg_byte_lanes WORD×BYTE3 cross bin
// =============================================================================
 
class seq_word_byte3 extends axi_base_seq;
  `uvm_object_utils(seq_word_byte3)
  constraint c_num_ovr { num_txns == 6; }
 
  function new(string name = "seq_word_byte3");
    super.new(name);
  endfunction
 
  virtual task body();
    send_reset();
 
    repeat (num_txns) begin
      bit [31:0] addr_b3;
      bit        is_wr;
      
      // Address with [1:0]=2'b11 for BYTE3 lane
      addr_b3 = (($urandom_range(0, 255)) * 4) + 3;
      is_wr   = $urandom_range(0, 1);
 
      begin
        axi_item it = axi_item::type_id::create("word_byte3");
        start_item(it);
        it.do_reset  = 0;
        it.is_write  = is_wr;
        it.id        = $urandom_range(0, 15);
        it.addr      = addr_b3;
        it.len       = 0;
        it.size      = AXI_SIZE_4B;  // WORD size
        it.raw_burst = AXI_BURST_INCR;
        it.wdata     = new[1]; it.wdata[0] = $urandom();
        it.wstrb     = new[1]; it.wstrb[0] = 4'hF;
        finish_item(it);
        
        `uvm_info("SEQ_BYTE3", 
          $sformatf("WORD at BYTE3: %s addr=0x%08h (addr[1:0]=%0b)", 
                    is_wr ? "WRITE" : "READ", addr_b3, addr_b3[1:0]), 
          UVM_MEDIUM)
      end
    end
  endtask
endclass
 
 
// =============================================================================
// SEQUENCE 10: FIXED Burst Type
// Targets: cg_protocol_errors cp_raw_burst FIXED bin
// =============================================================================
 
class seq_fixed_burst extends axi_base_seq;
  `uvm_object_utils(seq_fixed_burst)
  constraint c_num_ovr { num_txns == 8; }
 
  function new(string name = "seq_fixed_burst");
    super.new(name);
  endfunction
 
  virtual task body();
    send_reset();
 
    repeat (num_txns) begin
      bit [31:0] base_addr;
      bit [7:0]  burst_len;
      bit        is_wr;
      
      base_addr  = ($urandom_range(0, 252)) * 4;
      burst_len  = $urandom_range(0, 3);  // 1-4 beats
      is_wr      = $urandom_range(0, 1);
 
      begin
        axi_item it = axi_item::type_id::create("fixed_burst");
        start_item(it);
        it.do_reset  = 0;
        it.is_write  = is_wr;
        it.id        = $urandom_range(0, 15);
        it.addr      = base_addr;
        it.len       = burst_len;
        it.size      = AXI_SIZE_4B;
        it.raw_burst = AXI_BURST_FIXED;  // FIXED burst type
        it.wdata     = new[burst_len + 1];
        it.wstrb     = new[burst_len + 1];
        foreach (it.wdata[i]) begin
          it.wdata[i] = $urandom();
          it.wstrb[i] = 4'hF;
        end
        finish_item(it);
        
        `uvm_info("SEQ_FIXED", 
          $sformatf("FIXED burst: %s len=%0d addr=0x%08h", 
                    is_wr ? "WRITE" : "READ", burst_len, base_addr), 
          UVM_MEDIUM)
      end
    end
  endtask
endclass
 
 
// =============================================================================
// TEST CLASSES - One test per sequence
// =============================================================================
 
// Test 1: AW Back-pressure
class test_aw_backpressure extends axi_base_test;
  `uvm_component_utils(test_aw_backpressure)
  
  function new(string name = "test_aw_backpressure", uvm_component parent = null);
    super.new(name, parent);
  endfunction
 
  virtual function void build_phase(uvm_phase phase);
    axi_driver::type_id::set_type_override(axi_driver_backpressure::get_type());
    axi_base_seq::type_id::set_type_override(seq_aw_backpressure::get_type());
    super.build_phase(phase);
  endfunction
 
  virtual task run_phase(uvm_phase phase);
    axi_driver_backpressure bp_drv;
    
    phase.raise_objection(this);
    
    // Get driver and configure back-pressure
    if (!$cast(bp_drv, env.agt.drv))
      `uvm_fatal("TEST", "Driver cast failed")
    
    bp_drv.enable_aw_backpressure = 1;
    void'(bp_drv.randomize());
    
    `uvm_info("TEST_AW_BP", "Starting AW back-pressure test", UVM_LOW)
    void'(seq.randomize());
    seq.start(env.agt.seqr);
    
    phase.drop_objection(this);
  endtask
endclass
 
 
// Test 2: W Back-pressure
class test_w_backpressure extends axi_base_test;
  `uvm_component_utils(test_w_backpressure)
  
  function new(string name = "test_w_backpressure", uvm_component parent = null);
    super.new(name, parent);
  endfunction
 
  virtual function void build_phase(uvm_phase phase);
    axi_driver::type_id::set_type_override(axi_driver_backpressure::get_type());
    axi_base_seq::type_id::set_type_override(seq_w_backpressure::get_type());
    super.build_phase(phase);
  endfunction
 
  virtual task run_phase(uvm_phase phase);
    axi_driver_backpressure bp_drv;
    
    phase.raise_objection(this);
    
    if (!$cast(bp_drv, env.agt.drv))
      `uvm_fatal("TEST", "Driver cast failed")
    
    bp_drv.enable_w_backpressure = 1;
    void'(bp_drv.randomize());
    
    `uvm_info("TEST_W_BP", "Starting W back-pressure test", UVM_LOW)
    void'(seq.randomize());
    seq.start(env.agt.seqr);
    
    phase.drop_objection(this);
  endtask
endclass
 
 
// Test 3: B Back-pressure
class test_b_backpressure extends axi_base_test;
  `uvm_component_utils(test_b_backpressure)
  
  function new(string name = "test_b_backpressure", uvm_component parent = null);
    super.new(name, parent);
  endfunction
 
  virtual function void build_phase(uvm_phase phase);
    axi_driver::type_id::set_type_override(axi_driver_backpressure::get_type());
    axi_base_seq::type_id::set_type_override(seq_b_backpressure::get_type());
    super.build_phase(phase);
  endfunction
 
  virtual task run_phase(uvm_phase phase);
    axi_driver_backpressure bp_drv;
    
    phase.raise_objection(this);
    
    if (!$cast(bp_drv, env.agt.drv))
      `uvm_fatal("TEST", "Driver cast failed")
    
    bp_drv.enable_b_backpressure = 1;
    void'(bp_drv.randomize());
    
    `uvm_info("TEST_B_BP", "Starting B back-pressure test", UVM_LOW)
    void'(seq.randomize());
    seq.start(env.agt.seqr);
    
    phase.drop_objection(this);
  endtask
endclass
 
 
// Test 4: AR Back-pressure
class test_ar_backpressure extends axi_base_test;
  `uvm_component_utils(test_ar_backpressure)
  
  function new(string name = "test_ar_backpressure", uvm_component parent = null);
    super.new(name, parent);
  endfunction
 
  virtual function void build_phase(uvm_phase phase);
    axi_driver::type_id::set_type_override(axi_driver_backpressure::get_type());
    axi_base_seq::type_id::set_type_override(seq_ar_backpressure::get_type());
    super.build_phase(phase);
  endfunction
 
  virtual task run_phase(uvm_phase phase);
    axi_driver_backpressure bp_drv;
    
    phase.raise_objection(this);
    
    if (!$cast(bp_drv, env.agt.drv))
      `uvm_fatal("TEST", "Driver cast failed")
    
    bp_drv.enable_ar_backpressure = 1;
    void'(bp_drv.randomize());
    
    `uvm_info("TEST_AR_BP", "Starting AR back-pressure test", UVM_LOW)
    void'(seq.randomize());
    seq.start(env.agt.seqr);
    
    phase.drop_objection(this);
  endtask
endclass
 
 
// Test 5: R Back-pressure
class test_r_backpressure extends axi_base_test;
  `uvm_component_utils(test_r_backpressure)
  
  function new(string name = "test_r_backpressure", uvm_component parent = null);
    super.new(name, parent);
  endfunction
 
  virtual function void build_phase(uvm_phase phase);
    axi_driver::type_id::set_type_override(axi_driver_backpressure::get_type());
    axi_base_seq::type_id::set_type_override(seq_r_backpressure::get_type());
    super.build_phase(phase);
  endfunction
 
  virtual task run_phase(uvm_phase phase);
    axi_driver_backpressure bp_drv;
    
    phase.raise_objection(this);
    
    if (!$cast(bp_drv, env.agt.drv))
      `uvm_fatal("TEST", "Driver cast failed")
    
    bp_drv.enable_r_backpressure = 1;
    void'(bp_drv.randomize());
    
    `uvm_info("TEST_R_BP", "Starting R back-pressure test", UVM_LOW)
    void'(seq.randomize());
    seq.start(env.agt.seqr);
    
    phase.drop_objection(this);
  endtask
endclass
 
 
// Test 6: Comprehensive Back-pressure (All channels)
class test_comprehensive_backpressure extends axi_base_test;
  `uvm_component_utils(test_comprehensive_backpressure)
  
  function new(string name = "test_comprehensive_backpressure", uvm_component parent = null);
    super.new(name, parent);
  endfunction
 
  virtual function void build_phase(uvm_phase phase);
    axi_driver::type_id::set_type_override(axi_driver_backpressure::get_type());
    axi_base_seq::type_id::set_type_override(seq_comprehensive_backpressure::get_type());
    super.build_phase(phase);
  endfunction
 
  virtual task run_phase(uvm_phase phase);
    axi_driver_backpressure bp_drv;
    
    phase.raise_objection(this);
    
    if (!$cast(bp_drv, env.agt.drv))
      `uvm_fatal("TEST", "Driver cast failed")
    
    // Enable all back-pressure modes
    bp_drv.enable_aw_backpressure = 1;
    bp_drv.enable_w_backpressure  = 1;
    bp_drv.enable_b_backpressure  = 1;
    bp_drv.enable_ar_backpressure = 1;
    bp_drv.enable_r_backpressure  = 1;
    void'(bp_drv.randomize());
    
    `uvm_info("TEST_COMP_BP", "Starting comprehensive back-pressure test (ALL channels)", UVM_LOW)
    void'(seq.randomize());
    seq.start(env.agt.seqr);
    
    phase.drop_objection(this);
  endtask
endclass
 
 
// Test 7: Medium Burst Length
class test_medium_burst extends axi_base_test;
  `uvm_component_utils(test_medium_burst)
  
  function new(string name = "test_medium_burst", uvm_component parent = null);
    super.new(name, parent);
  endfunction
 
  virtual function void build_phase(uvm_phase phase);
    axi_base_seq::type_id::set_type_override(seq_medium_burst::get_type());
    super.build_phase(phase);
  endfunction
endclass
 
 
// Test 8: Read Errors
class test_read_errors extends axi_base_test;
  `uvm_component_utils(test_read_errors)
  
  function new(string name = "test_read_errors", uvm_component parent = null);
    super.new(name, parent);
  endfunction
 
  virtual function void build_phase(uvm_phase phase);
    axi_base_seq::type_id::set_type_override(seq_read_errors::get_type());
    super.build_phase(phase);
  endfunction
endclass
 
 
// Test 9: WORD × BYTE3
class test_word_byte3 extends axi_base_test;
  `uvm_component_utils(test_word_byte3)
  
  function new(string name = "test_word_byte3", uvm_component parent = null);
    super.new(name, parent);
  endfunction
 
  virtual function void build_phase(uvm_phase phase);
    axi_base_seq::type_id::set_type_override(seq_word_byte3::get_type());
    super.build_phase(phase);
  endfunction
endclass
 
 
// Test 10: FIXED Burst
class test_fixed_burst extends axi_base_test;
  `uvm_component_utils(test_fixed_burst)
  
  function new(string name = "test_fixed_burst", uvm_component parent = null);
    super.new(name, parent);
  endfunction
 
  virtual function void build_phase(uvm_phase phase);
    axi_base_seq::type_id::set_type_override(seq_fixed_burst::get_type());
    super.build_phase(phase);
  endfunction
endclass
 
 
// Test 11: MASTER COVERAGE CLOSURE TEST - Runs all sequences
class test_coverage_closure extends axi_base_test;
  `uvm_component_utils(test_coverage_closure)
  
  function new(string name = "test_coverage_closure", uvm_component parent = null);
    super.new(name, parent);
  endfunction
 
  virtual function void build_phase(uvm_phase phase);
    axi_driver::type_id::set_type_override(axi_driver_backpressure::get_type());
    super.build_phase(phase);
  endfunction
 
  virtual task run_phase(uvm_phase phase);
    axi_driver_backpressure bp_drv;
    seq_comprehensive_backpressure bp_seq;
    seq_medium_burst               med_seq;
    seq_read_errors                err_seq;
    seq_word_byte3                 b3_seq;
    seq_fixed_burst                fix_seq;
    
    phase.raise_objection(this);
    
    if (!$cast(bp_drv, env.agt.drv))
      `uvm_fatal("TEST", "Driver cast failed")
    
    `uvm_info("TEST_COV_CLOSURE", "========================================", UVM_LOW)
    `uvm_info("TEST_COV_CLOSURE", "COVERAGE CLOSURE TEST - Running all sequences", UVM_LOW)
    `uvm_info("TEST_COV_CLOSURE", "========================================", UVM_LOW)
    
    // 1. Comprehensive back-pressure (covers all 8 stability assertions)
    `uvm_info("TEST_COV_CLOSURE", "Phase 1: Comprehensive back-pressure test", UVM_LOW)
    bp_drv.enable_aw_backpressure = 1;
    bp_drv.enable_w_backpressure  = 1;
    bp_drv.enable_b_backpressure  = 1;
    bp_drv.enable_ar_backpressure = 1;
    bp_drv.enable_r_backpressure  = 1;
    void'(bp_drv.randomize());
    
    bp_seq = seq_comprehensive_backpressure::type_id::create("bp_seq");
    void'(bp_seq.randomize());
    bp_seq.start(env.agt.seqr);
    
    // Disable back-pressure for remaining tests
    bp_drv.enable_aw_backpressure = 0;
    bp_drv.enable_w_backpressure  = 0;
    bp_drv.enable_b_backpressure  = 0;
    bp_drv.enable_ar_backpressure = 0;
    bp_drv.enable_r_backpressure  = 0;
    
    // 2. Medium burst length
    `uvm_info("TEST_COV_CLOSURE", "Phase 2: Medium burst length test", UVM_LOW)
    med_seq = seq_medium_burst::type_id::create("med_seq");
    void'(med_seq.randomize());
    med_seq.start(env.agt.seqr);
    
    // 3. Read errors
    `uvm_info("TEST_COV_CLOSURE", "Phase 3: Read error scenarios", UVM_LOW)
    err_seq = seq_read_errors::type_id::create("err_seq");
    void'(err_seq.randomize());
    err_seq.start(env.agt.seqr);
    
    // 4. WORD × BYTE3
    `uvm_info("TEST_COV_CLOSURE", "Phase 4: WORD × BYTE3 coverage", UVM_LOW)
    b3_seq = seq_word_byte3::type_id::create("b3_seq");
    void'(b3_seq.randomize());
    b3_seq.start(env.agt.seqr);
    
    // 5. FIXED burst
    `uvm_info("TEST_COV_CLOSURE", "Phase 5: FIXED burst type", UVM_LOW)
    fix_seq = seq_fixed_burst::type_id::create("fix_seq");
    void'(fix_seq.randomize());
    fix_seq.start(env.agt.seqr);
    
    `uvm_info("TEST_COV_CLOSURE", "========================================", UVM_LOW)
    `uvm_info("TEST_COV_CLOSURE", "COVERAGE CLOSURE TEST COMPLETE", UVM_LOW)
    `uvm_info("TEST_COV_CLOSURE", "========================================", UVM_LOW)
    
    phase.drop_objection(this);
  endtask
endclass


// =============================================================================
// Top
// =============================================================================
module tb_top;

  logic ACLK;
  initial ACLK = 1'b0;
  always #5 ACLK = ~ACLK;

  axi_if #(
    .ADDR_WIDTH(32),
    .DATA_WIDTH(32),
    .ID_WIDTH  (4)
  ) _if (.ACLK(ACLK));

  axi_mem #(
    .ADDR_WIDTH(32),
    .DATA_WIDTH(32),
    .ID_WIDTH  (4),
    .MEM_DEPTH (256)
  ) dut (
    .ACLK    (ACLK),
    .ARESETn (_if.ARESETn),

    .AWID    (_if.AWID),
    .AWADDR  (_if.AWADDR),
    .AWLEN   (_if.AWLEN),
    .AWSIZE  (_if.AWSIZE),
    .AWBURST (_if.AWBURST),
    .AWVALID (_if.AWVALID),
    .AWREADY (_if.AWREADY),

    .WDATA   (_if.WDATA),
    .WSTRB   (_if.WSTRB),
    .WLAST   (_if.WLAST),
    .WVALID  (_if.WVALID),
    .WREADY  (_if.WREADY),

    .BID     (_if.BID),
    .BRESP   (_if.BRESP),
    .BVALID  (_if.BVALID),
    .BREADY  (_if.BREADY),

    .ARID    (_if.ARID),
    .ARADDR  (_if.ARADDR),
    .ARLEN   (_if.ARLEN),
    .ARSIZE  (_if.ARSIZE),
    .ARBURST (_if.ARBURST),
    .ARVALID (_if.ARVALID),
    .ARREADY (_if.ARREADY),

    .RID     (_if.RID),
    .RDATA   (_if.RDATA),
    .RRESP   (_if.RRESP),
    .RLAST   (_if.RLAST),
    .RVALID  (_if.RVALID),
    .RREADY  (_if.RREADY)
  );

  initial begin
    uvm_config_db #(virtual axi_if)::set(null, "*", "axi_vif", _if);
    run_test("axi_base_test");
  end

  initial begin
    #2_000_000;
    `uvm_fatal("TIMEOUT", "Simulation watchdog timeout")
  end

endmodule
