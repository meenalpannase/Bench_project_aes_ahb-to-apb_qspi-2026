`default_nettype none

module top_vio_test(
    input  wire       sys_clk, // Physical clock from your FPGA board
    output wire [7:0] leds     // Physical LEDs on your FPGA board
);

wire hclk,pclk;

 clk_wiz_0 instance_name
   (
    // Clock out ports
    .clk_out1(hclk),     // output clk_out1
    .clk_out2(pclk),     // output clk_out2
   // Clock in ports
    .clk_in1(sys_clk)      // input clk_in1
);



    // AHB Signals (Driven by VIO)
    wire        hresetn;
    wire        hsel;
    wire        hready;
    wire [1:0]  htrans;
    wire        hwrite;
    wire [2:0]  hsize;
    wire [31:0] haddr;
    wire [31:0] hwdata;

    // AHB Responses (Read by VIO)
    wire [31:0] hrdata;
    wire        hreadyout;
    wire        hresp;

    // APB Signals (Monitored by ILA)
    wire [7:0]  psel;
    wire        penable;
    wire [31:0] paddr;
    wire        pwrite;
    wire [31:0] pwdata;
    wire [3:0]  pstrb;
    
    wire [255:0] prdata_bus;
    wire [7:0]   pready_bus;
    wire [7:0]   pslverr_bus;

    // 1. Instantiate VIO
    vio_0 u_vio (
        .clk        (hclk),
        .probe_in0  (hrdata),
        .probe_in1  (hreadyout),
        .probe_in2  (hresp),
        .probe_out0 (hresetn),
        .probe_out1 (hsel),
        .probe_out2 (hready),
        .probe_out3 (htrans),
        .probe_out4 (hwrite),
        .probe_out5 (hsize),
        .probe_out6 (haddr),
        .probe_out7 (hwdata)
    );

    // 2. Instantiate Your Bridge (DUT)
    ahb2apb_bridge #(
        .NUM_SLAVES(8),
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32),
        .SLAVE_ADDR_BITS(10),
        .TIMEOUT_CYCLES(10),
        .BASE_ADDR(32'h0000_0000)
    ) u_bridge (
        .hclk       (sys_clk), // Tied to sys_clk for this test
        .hresetn    (hresetn),
        .hsel       (hsel),
        .hready     (hready),
        .haddr      (haddr),
        .htrans     (htrans),
        .hwrite     (hwrite),
        .hsize      (hsize),
        .hwdata     (hwdata),
        .hrdata     (hrdata),
        .hreadyout  (hreadyout),
        .hresp      (hresp),
        
        .pclk       (sys_clk), // Tied to sys_clk for this test
        .presetn    (hresetn),
        .psel       (psel),
        .penable    (penable),
        .paddr      (paddr),
        .pwrite     (pwrite),
        .pwdata     (pwdata),
        .pstrb      (pstrb),
        .prdata_bus (prdata_bus),
        .pready_bus (pready_bus),
        .pslverr_bus(pslverr_bus)
    );

    // 3. Instantiate APB LED Slave
    apb_led_slave #(
        .NUM_SLAVES(8),
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32)
    ) u_slave (
        .pclk       (sys_clk),
        .presetn    (hresetn),
        .paddr      (paddr),
        .psel       (psel),
        .penable    (penable),
        .pwrite     (pwrite),
        .pwdata     (pwdata),
        .pstrb      (pstrb),
        .prdata_bus (prdata_bus),
        .pready_bus (pready_bus),
        .pslverr_bus(pslverr_bus),
        .leds       (leds)
    );

    // 4. Instantiate ILA
    ila_0 u_ila (
        .clk    (pclk),
        .probe0 (psel),
        .probe1 (penable),
        .probe2 (paddr),
        .probe3 (pwrite),
        .probe4 (pwdata)
    );

endmodule