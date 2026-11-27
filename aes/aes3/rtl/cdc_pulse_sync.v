// Safely carries a single-cycle pulse from src_clk into dst_clk, when
// the two clocks are asynchronous to each other. A single-cycle pulse
// can't be passed through a plain 2-FF synchronizer directly: if
// dst_clk is faster than or comparable to src_clk, the pulse can be
// too narrow to be reliably captured on a destination edge and gets
// silently dropped. This uses the standard toggle scheme instead: the
// source pulse toggles a level in src_clk, that level is 2-FF
// synchronized into dst_clk, and an edge detector there produces a
// clean single dst_clk-cycle pulse. This works for any clock ratio and
// never drops or duplicates a pulse, as long as src_in is a genuine
// single-cycle pulse and consecutive pulses are spaced at least about
// 3 dst_clk periods apart (closer than that and they can merge into
// what looks like a single destination pulse) - don't tie src_in to a
// level held high for multiple src_clk cycles.
//
// Used for: key_load_pulse, iv_load_pulse, zeroize_pulse (all from
// register_bank.v, pclk domain) into control_fsm.v (crypto_clk
// domain). One instance per pulse - don't share one instance across
// multiple unrelated pulses, since a toggle can only encode "one pulse
// happened", not which one or how many.

module cdc_pulse_sync (
    input  wire src_clk,
    input  wire src_rst_n,
    input  wire src_in,        // single-cycle pulse in the src_clk domain

    input  wire dst_clk,
    input  wire dst_rst_n,
    output wire dst_pulse      // single-cycle pulse in the dst_clk domain
);

    // source side: toggle on every input pulse
    reg src_toggle;
    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n)
            src_toggle <= 1'b0;
        else if (src_in)
            src_toggle <= ~src_toggle;
    end

    // destination side: 2-FF sync then edge detect
    reg dst_sync0, dst_sync1, dst_sync2;
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            dst_sync0 <= 1'b0;
            dst_sync1 <= 1'b0;
            dst_sync2 <= 1'b0;
        end else begin
            dst_sync0 <= src_toggle;  // first stage, may go metastable, expected and normal
            dst_sync1 <= dst_sync0;   // second stage, resolved, safe to use
            dst_sync2 <= dst_sync1;   // one cycle behind dst_sync1, for edge detection only
        end
    end

    assign dst_pulse = dst_sync1 ^ dst_sync2;

endmodule