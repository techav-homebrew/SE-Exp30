/******************************************************************************
 * SE-Exp30 MacSE Accelerator
 * techav
 * 2021-03-20
 * Processor Accelerator System Translation Engine
 ******************************************************************************
 * Handles all logic to translate the Mac SE 68000 PDS bus to the 68030 bus as 
 * well as additional logic for interfacing with the 68882 FPU.
 *****************************************************************************/

module paste (
    inout wire          ncpuReset,          // 68030 reset signal (tristate)
    inout wire          ncpuHalt,           // 68030 halt signal (tristate)
    input wire          ncpuDS,             // 68030 data strobe signal
    input wire          ncpuAS,             // 68030 address strobe signal
    inout wire          ncpuDsack0,         // 68030 DS Ack 0 signal
    inout wire          ncpuDsack1,         // 68030 DS Ack 1 signal
    input wire          cpuSize0,           // 68030 Size 0 signal
    input wire          cpuSize1,           // 68030 Size 1 signal
    input wire          cpuA0,              // 68030 Address 0 signal
    input logic [23:20] cpuAddrHi,          // 68030 Address Hi (16MB) signals
    input logic [19:13] cpuAddrMid,         // 68030 Address Mid (FPU decode) signals
    output wire         ncpuAvec,           // 68030 Autovector request signal
    input logic [2:0]   cpuFC,              // 68030 Function Code signals
    input wire          cpuClock,           // 68030 Primary CPU Clock signal
    input wire          cpuRnW,             // 68030 Read/Write signal
    input wire          ncpuBG,             // 68030 Bus Grant signal
    inout wire          ncpuBerr,           // 68030 Bus Error signal
    inout wire          ncpuCiin,           // 68030 Cache Inhibit signal
    input wire          npdsReset,          // PDS Reset signal
    inout wire          npdsLds,            // PDS Lower Data Strobe signal
    inout wire          npdsUds,            // PDS Upper Data Strobe signal
    inout wire          npdsAs,             // PDS Address Strobe signal
    input wire          npdsDtack,          // PDS Data Xfer Ack signal
    input wire          npdsBg,             // PDS Bus Grant signal
    output wire         npdsBGack,          // PDS Bus Grant Ack signal
    output wire         npdsBr,             // PDS Bus Request signal
    inout wire          npdsVma,            // PDS Valid Memory Addr signal
    input wire          npdsVpa,            // PDS Valid Peripheral Addr signal
    input wire          pdsC8m,             // PDS 8MHz System Clock signal
    input wire          pdsClockE,          // PDS 800kHz 6800 bus E clock
    output wire         nbufDhiEn,          // Data buffer CPU[31:24] <=> PDS[15:8]
    output wire         nbufDlo1En,         // Data buffer CPU[23:16] <=> PDS[7:0]
    output wire         nbufDlo2En,         // Data buffer CPU[31:24] <=> PDS[7:0]
    output wire         bufDDir,            // Data buffer direction
    output wire         nbufCEn,            // Control signal buffer enable
    output wire         nbufAEn,            // Address buffer enable
    input wire          nfpuSense,          // FPU Presence Detect signal
    output wire         nfpuCe              // FPU Chip Select signal
);

// define state machine states
parameter
    S0  =   0,
    S1  =   1,
    S2  =   2,
    S3  =   3,
    S4  =   4,
    S5  =   5,
    S6  =   6,
    S7  =   7,
    S8  =   8;

logic [3:0] busState;           // state machine for 68000 bus
logic [1:0] termState;          // state machine for 68030 bus termination
logic [1:0] resetgenState;      // state machine for nCpuReset generator
logic [1:0] cycleEndState;      // state machine for 68030 bus cycle end monitor

wire nUD, nLD;                  // intermediate data strobe signals

// 68000 bus state machine
// synchronous to 8MHz 68000 clock
always @(posedge pdsC8m or negedge npdsReset) begin
    if(npdsReset == 0) busState <= S0;
    else begin
        case(busState) 
            S0 : begin
                // idle state, wait for cpu to begin bus cycle
                if(ncpuAS == 0) busState <= S1;
                else busState <= S0;
            end
            S1 : begin
                // 68000 bus cycle state 2/3
                // progress immediately
                busState <= S2;
            end
            S2 : begin
                // 68000 bus cycle state 4/5
                // wait for PDS DTACK or PDS VPA
                if(npdsDtack == 0) busState <= S3;
                else if(npdsVpa == 0) busState <= S4;
                else busState <= S2;
            end
            S3 : begin
                // 68000 bus cycle state 6/7
                // end 68000 bus cycle
                // wait for cycleEndState == S2
                if(cycleEndState == S2) busState <= S0;
                else busState <= S3;
            end
            S4 : begin
                // 6800 bus cycle state 1
                // wait for E clock = 0
                if(pdsClockE == 0) busState <= S5;
                else busState <= S4;
            end
            S5 : begin
                // 6800 bus cycle state 2
                // wait for E clock = 1
                if(pdsClockE == 1) busState <= S6;
                else busState <= S5;
            end
            S6 : begin
                // 6800 bus cycle state 3
                // progress immediately
                busState <= S7;
            end
            S7 : begin
                // 6800 bus cycle state 4
                // progress immediately
                busState <= S8;
            end
            S8 : begin
                // 6800 bus cycle state 5
                // wait for cycleEndState == S2
                if(cycleEndState == S2) busState <= S0;
                else busState <= S8;
            end
            default: begin
                // how did we end up here?
                busState <= S0;
            end
        endcase
    end
end

// 68030 bus termination state machine
// drives CPU DSACKx signals
// synchronous to CPU clock
always @(posedge cpuClock or negedge npdsReset) begin
    if(npdsReset == 0) termState <= S0;
    else begin
        case(termState)
            S0 : begin
                // idle, wait for busState
                if(busState == S3 && pdsC8m == 1) termState <= S1;
                else if(busState == S8 && pdsC8m == 1) termState <= S1;
                else termState <= S0;
            end
            S1 : begin
                // assert 68030 bus termination
                // progress immediately
                termState <= S2;
            end
            S2 : begin
                // wait for busState
                if(busState == S0) termState <= S0;
                else termState <= S2;
            end
            default: begin
                // how did we end up here?
                termState <= S0;
            end
        endcase
    end
end

// 68030 bus cycle end monitor
// watches for 68030 ending a bus cycle (de-asserting AS)
// synchronous to CPU clock
always @(posedge cpuClock or negedge npdsReset) begin
    if(npdsReset == 0) cycleEndState <= S0;
    else begin
        case(cycleEndState)
            S0 : begin
                if(busState != S0) cycleEndState <= S1;
                else cycleEndState <= S0;
            end
            S1 : begin
                if(ncpuAS == 1) cycleEndState <= S2;
                else cycleEndState <= S1;
            end
            S2: begin
                if(busState == S0) cycleEndState <= S0;
                else cycleEndState <= S2;
            end
            default: begin
                // how did get end up here?
                cycleEndState <= S0;
            end
        endcase
    end
end

// state machine for power on reset
always @(posedge cpuClock or negedge npdsReset) begin
    // sync state machine clocked by primary CPU clock with async reset
    if(npdsReset == 1'b0) begin
        resetgenState <= S0;
    end else begin
        case(resetgenState)
            S0 : begin
                // wait for deassertion of npdsReset
                if(npdsReset == 1'b1) begin
                    resetgenState <= S1;
                end else begin
                    // shouldn't actually end up here
                    resetgenState <= S0;
                end
            end
            S1 : begin
                // wait for Bus Grant from SE
                if(npdsBg == 1'b0) begin
                    resetgenState <= S2;
                end else begin
                    resetgenState <= S1;
                end
            end
            S2 : begin
                // this is actually our idle state.
                // stay here until the system resets again.
                if(npdsReset == 1'b1) begin
                    resetgenState <= S2;
                end else begin
                    resetgenState <= S0;
                end
            end
            default: begin
                // really shouldn't be here
                resetgenState <= S0;
            end
        endcase
    end
end

// combinatorial logic
assign nUD = ~(~cpuA0 || cpuRnW);
assign nLD = ~(cpuA0 || ~cpuSize0 || cpuSize1 || cpuRnW);

always_comb begin
    // CPU reset signals
    if(resetgenState != S2) begin
        ncpuReset <= 1'b0;
        ncpuHalt <= 1'b0;
    end else begin
        ncpuReset <= 1'bz;
        ncpuHalt <= 1'bz;
    end

    // bus request & grant
    if(resetgenState == S0) begin
        npdsBr <= 1'bz;
    end else begin
        npdsBr <= 1'b0;
    end
    if(resetgenState == S2) begin
        npdsBGack <= 1'b0;
    end else begin
        npdsBGack <= 1'bz;
    end

    // buffer enable signals
    if(ncpuBG == 1'b1) begin
        if(nUD == 0 && npdsBg == 0) begin
            nbufDhiEn <= 1'b0;
        end else begin
            nbufDhiEn <= 1'b1;
        end
        if(nLD == 0 && nUD == 1 && npdsBg == 0) begin
            nbufDlo2En <= 1'b0;
        end else begin
            nbufDlo2En <= 1'b1;
        end
        if(nLD == 0 && nUD == 0 && npdsBg == 0) begin
            nbufDlo1En <= 1'b0;
        end else begin
            nbufDlo1En <= 1'b1;
        end
        if(npdsBg <= 1'b0) begin
            nbufAEn <= 1'b0;
            nbufCEn <= 1'b0;
        end else begin
            nbufAEn <= 1'b1;
            nbufCEn <= 1'b1;
        end
    end else begin
        nbufDhiEn <= 1'b1;
        nbufDlo2En <= 1'b1;
        nbufDlo1En <= 1'b1;
        nbufAEn <= 1'b1;
        nbufCEn <= 1'b1;
    end

    // data buffer direction
    bufDDir <= cpuRnW;

    // CPU cache inhibit
    if(cpuAddrHi >= 4'h6) begin
        ncpuCiin <= 1'b0;
    end else begin
        ncpuCiin <= 1'bz;
    end

    // Upper/Lower data strobes
    if(npdsBg == 1) begin
        npdsUds <= 1'bZ;
        npdsLds <= 1'bZ;
    end else begin
        if(cpuRnW == 1 && busState == S1) begin
            npdsUds <= nUD;
            npdsLds <= nLD;
        end else if (busState == S2 || busState == S3 ||
                     busState == S4 || busState == S5 ||
                     busState == S6 || busState == S7 ||
                     busState == S8) begin
            npdsUds <= nUD;
            npdsLds <= nLD;
        end else begin
            npdsUds <= 1;
            npdsLds <= 1;
        end
    end

    // Address strobe
    if(npdsBg == 1) npdsAs <= 1'bZ;
    else begin
        if(busState != S0) npdsAs <= 0;
        else npdsAs <= 1;
    end

    // 6800 bus VMA signal
    if(npdsBg == 1) npdsVma <= 1'bZ;
    else begin
        if(busState == S5 || busState == S6 || 
            busState == S7 || busState == S8) begin
                npdsVma <= 0;
        end else npdsVma <= 1;
    end

    // 68030 bus termination signals
    // FPU will terminate on its own
    if(termState == S1) begin
        if(cpuAddrHi < 4'h5 && cpuFC < 3'h7) begin
            // RAM/ROM access - 16-bit
            ncpuDsack0 <= 1'bZ;
            ncpuDsack1 <= 0;
            ncpuAvec <= 1'bZ;
            ncpuBerr <= 1'bZ;
        end else if(cpuAddrHi >= 4'h5 && cpuFC < 3'h7) begin
            // peripheral access - 8-bit
            ncpuDsack0 <= 0;
            ncpuDsack1 <= 1'bZ;
            ncpuAvec <= 1'bZ;
            ncpuBerr <= 1'bZ;
        end else if(cpuFC == 3'h7) begin
            // autovector interrupt
            ncpuAvec <= 0;
            ncpuDsack0 <= 1'bZ;
            ncpuDsack1 <= 1'bZ;
            ncpuBerr <= 1'bZ;
        end else begin
            // this is an odd case. how did it happen?
            // may as well throw an error
            ncpuBerr <= 0;
            ncpuDsack0 <= 1'bZ;
            ncpuDsack1 <= 1'bZ;
            ncpuAvec <= 1'bZ;
        end
    end else begin
        ncpuBerr <= 1'bZ;
        ncpuDsack0 <= 1'bZ;
        ncpuDsack1 <= 1'bZ;
        ncpuAvec <= 1'bZ;
    end

    // FPU chip enable & presence detect
    if(cpuAddrMid == 7'h11 && cpuFC == 3'h7 && ncpuAS) begin
        nfpuCe <= 1'b0;
        if(nfpuSense == 1'b1) begin
            // pulled high means FPU missing. assert bus error
            ncpuBerr <= 1'b0;
        end else begin
            ncpuBerr <= 1'bz;
        end
    end else begin
        nfpuCe <= 1'b1;
        ncpuBerr <= 1'bz;
    end
end

endmodule