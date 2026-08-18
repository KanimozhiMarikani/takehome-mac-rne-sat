`timescale 1ns/1ps
//
// mac_rne_sat -- implement your golden solution in this file per
// docs/spec.md, and push it to your fork's mac_rne_sat_golden branch.
//
module mac_rne_sat (
    input  wire                clk,       // Input clock domain
    input  wire                rst,       // synchronous, active-high
    input  wire                en,        // accumulate a*b this cycle
    input  wire                clr,       // clear accumulator this cycle
    input  wire                rd,        // request readout snapshot this cycle
    input  wire  signed [7:0]  a,
    input  wire  signed [7:0]  b,
    output reg   signed [15:0] res,       // rounded + saturated snapshot
    output reg                 res_valid, // 1-cycle pulse, one cycle after rd
    output reg                 ovf        // sticky saturation flag
);

    // 28-bit signed accumulator
    reg signed [27:0] acc;

    // Product and sign-extended accumulate input.
    wire signed [15:0] prod;
    wire signed [27:0] prod_ext;

    wire signed [27:0] q;
    wire signed [27:0] q_ext;
    wire signed [27:0] q_scaled;
    wire signed [27:0] rem;
    wire signed [19:0] rounded;
    wire signed [15:0] out_val;
    wire saturating;

    assign prod = a * b;
    assign prod_ext = {{12{prod[15]}}, prod};

    // Readout math uses the snapshot accumulator value, before the same-cycle
    // update. This makes the readout a pure function of the old acc.
    assign q = acc >>> 8;
    assign q_ext = {{8{q[19]}}, q[19:0]};
    assign q_scaled = q_ext << 8;
    assign rem = acc - q_scaled;

    assign rounded = (rem < 28'sd128) ? q :
                     ((rem > 28'sd128) ? (q + 28'sd1) :
                     ((q[0] == 1'b0) ? q : (q + 28'sd1)));

    assign out_val = (rounded > 20'sd32767) ? 16'sd32767 :
                     ((rounded < -20'sd32768) ? -16'sd32768 : rounded[15:0]);
    assign saturating = (rounded > 20'sd32767) || (rounded < -20'sd32768);

    always @(posedge clk) begin
        if (rst) begin
            acc       <= 28'sd0;
            res       <= 16'sd0;
            res_valid <= 1'b0;
            ovf       <= 1'b0;
        end
        else begin
            // Accumulator update. The readout snapshot is always the old acc,
            // regardless of whether en/clr/rd are also asserted this cycle.
            if (clr) begin
                if (en)
                    acc <= prod_ext;
                else
                    acc <= 28'sd0;
            end
            else if (en) begin
                acc <= acc + prod_ext;
            end

            // One-cycle delayed acknowledgment of rd.
            res_valid <= rd;

            // Readout only when requested; hold between reads.
            if (rd)
                res <= out_val;

            // Sticky overflow: set on saturating readout, clear only on clr.
            if (rd && saturating)
                ovf <= 1'b1;
            else if (clr)
                ovf <= 1'b0;
        end
    end
endmodule
