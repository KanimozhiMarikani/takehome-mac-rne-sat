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

    // Product
    wire signed [15:0] prod;
    wire signed [27:0] prod_ext;

    assign prod     = a * b;
    assign prod_ext = {{12{prod[15]}}, prod};

    // ------------------------------------------------------------------
    // Readout pipeline.
    // rd_pending is the registered rd request.
    // The combinational rounding logic observes the current acc, so at
    // the clock edge the snapshot is the pre-update accumulator value.
    // ------------------------------------------------------------------
    reg               rd_pending;
    reg signed [15:0] rd_result;
    reg               rd_saturated;

    reg signed [27:0] q;
    reg signed [27:0] r;
    reg signed [27:0] rounded;

    // Rounding and saturation of the current accumulator.
    always @* begin
        // Arithmetic shift gives:
        // q = floor(acc / 256)
        q = acc >>> 8;

        // Remainder is guaranteed to be 0..255.
        r = acc - (q <<< 8);

        // Round-to-nearest, ties-to-even.
        if (r < 28'sd128) begin
            rounded = q;
        end
        else if (r > 28'sd128) begin
            rounded = q + 28'sd1;
        end
        else begin
            // Exact half-way case.
            if (q[0] == 1'b0)
                rounded = q;
            else
                rounded = q + 28'sd1;
        end

        // Saturate only after rounding.
        if (rounded > 28'sd32767) begin
            rd_result    = 16'sh7fff;
            rd_saturated = 1'b1;
        end
        else if (rounded < -28'sd32768) begin
            rd_result    = -16'sd32768;
            rd_saturated = 1'b1;
        end
        else begin
            rd_result    = rounded[15:0];
            rd_saturated = 1'b0;
        end
    end

    // ------------------------------------------------------------------
    // Sequential logic
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            acc         <= 28'sd0;
            res         <= 16'sd0;
            res_valid   <= 1'b0;
            ovf         <= 1'b0;

            rd_pending  <= 1'b0;
        end
        else begin
            // ==========================================================
            // Readout response.
            // ==========================================================
            res       <= rd_result;
            res_valid <= rd_pending;

            // Sticky overflow.
            //
            // A saturating readout becoming valid this cycle has
            // priority over clr.
            if (rd_pending && rd_saturated)
                ovf <= 1'b1;
            else if (clr)
                ovf <= 1'b0;

            // ==========================================================
            // Capture current-cycle read request.
            // ==========================================================
            rd_pending <= rd;
            // ==========================================================
            if (clr) begin
                if (en)
                    acc <= prod_ext;
                else
                    acc <= 28'sd0;
            end
            else if (en) begin
                acc <= acc + prod_ext;
            end
        end
    end
endmodule