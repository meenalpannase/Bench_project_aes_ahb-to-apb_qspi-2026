`default_nettype none

module ahb_capture_fsm #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  wire hclk,
    input  wire hresetn,
    input  wire hsel,
    input  wire hready,
    input  wire [ADDR_WIDTH-1:0] haddr,
    input  wire [1:0] htrans,
    input  wire hwrite,
    input  wire [2:0] hsize,
    input  wire [DATA_WIDTH-1:0] hwdata,

    output reg  [DATA_WIDTH-1:0] hrdata,
    output reg  hreadyout,
    output reg  hresp,

    output reg  xfer_valid,
    output wire [ADDR_WIDTH-1:0] xfer_addr,
    output wire xfer_write,
    output wire [2:0] xfer_size,
    output reg  [DATA_WIDTH-1:0] xfer_wdata,

    input  wire resp_valid,
    input  wire [DATA_WIDTH-1:0] resp_rdata,
    input  wire resp_code
);

    localparam TRANS_NONSEQ = 2'b10;
    localparam TRANS_SEQ = 2'b11;
    localparam RESP_OKAY = 1'b0;
    localparam RESP_ERROR = 1'b1;

    localparam IDLE  = 2'b00;
    localparam DATA  = 2'b01;
    localparam WAIT  = 2'b10;
    localparam ERROR = 2'b11;

    reg [1:0] ct_st, nt_st;

    // AHB is pipelined: the address phase occurs one cycle before the data phase.
    // We must latch the address and control signals because the AHB master 
    // might change them in the next cycle before the backend is ready.
    reg [ADDR_WIDTH-1:0] pending_addr;
    reg pending_write;
    reg [2:0] pending_size;

    // Filter out AHB IDLE (00) and BUSY (01) transfers. We only care about 
    // NONSEQ and SEQ transfers which represent actual data requests.
    wire xfer_req = hsel && hready && (htrans == TRANS_NONSEQ || htrans == TRANS_SEQ);

    assign xfer_addr  = pending_addr;
    assign xfer_write = pending_write;
    assign xfer_size  = pending_size;

    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn) 
            ct_st <= IDLE;
        else 
           ct_st <= nt_st;
    end

    // Next State Logic
    always @(*) begin
        nt_st = ct_st;
        case (ct_st)
            IDLE: begin
                if (xfer_req) 
                    nt_st = DATA;
            end
            DATA: begin
                // Automatically transition to WAIT to stall the bus 
                // while the backend processes the captured transfer.
                nt_st = WAIT;
            end
            WAIT: begin
                if (resp_valid) begin
                    if (resp_code == RESP_ERROR) 
                        nt_st = ERROR;
                    else 
                        nt_st = IDLE;
                end
            end
            ERROR: begin
                // AHB spec requires exactly a 2-cycle error response.
                // The first cycle happens in the WAIT -> ERROR transition.
                // The second cycle happens in this ERROR -> IDLE transition.
                nt_st = IDLE;
            end
            default: nt_st = IDLE;
        endcase
    end

    // Output Logic
    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            hreadyout <= 1'b1;
            hresp <= RESP_OKAY;
            hrdata <= {DATA_WIDTH{1'b0}};
            xfer_valid <= 1'b0;
            xfer_wdata <= {DATA_WIDTH{1'b0}};
            pending_addr <= {ADDR_WIDTH{1'b0}};
            pending_write <= 1'b0;
            pending_size <= 3'b000;
        end else begin
            // Default xfer_valid to 0 so it only pulses for one cycle
            xfer_valid <= 1'b0; 

            // Capture address phase info. hwdata is NOT valid yet.
            if (ct_st == IDLE && xfer_req) begin
                pending_addr  <= haddr;
                pending_write <= hwrite;
                pending_size  <= hsize;
            end

            case (nt_st)
                IDLE: begin
                    hreadyout <= 1'b1;
                    // Fulfill the 2nd cycle of the AHB error response:
                    // hreadyout goes HIGH while hresp remains ERROR.
                    if (ct_st == ERROR) 
                        hresp <= RESP_ERROR;
                    else 
                        hresp <= RESP_OKAY;
                end
                DATA: begin
                    hreadyout <= 1'b0; // Start stalling the bus (wait states)
                    hresp <= RESP_OKAY;
                end
                WAIT: begin
                    hreadyout <= 1'b0;
                    hresp <= RESP_OKAY;
                    if (ct_st == DATA) begin
                        // hwdata is now valid (data phase). 
                        // Pulse xfer_valid and pass data to the backend.
                        xfer_valid <= 1'b1;
                        xfer_wdata <= pending_write ? hwdata : {DATA_WIDTH{1'b0}};
                    end
                end
                ERROR: begin
                    // Fulfill the 1st cycle of the AHB error response:
                    // hreadyout is LOW and hresp is set to ERROR.
                    hreadyout <= 1'b0;
                    hresp <= RESP_ERROR;
                end
            endcase

            if (ct_st == WAIT && resp_valid && (resp_code == RESP_OKAY)) begin
                // Prevent leaking previous read data or garbage during a write response
                hrdata <= pending_write ? {DATA_WIDTH{1'b0}} : resp_rdata;
            end
        end
    end
endmodule