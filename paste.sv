/******************************************************************************
 * MacSE Accelerator
 * techav
 * 2021-03-20
 * Processor Accelerator System Translation Engine
 ******************************************************************************
 * Handles all logic to translate the Mac SE 68000 PDS bus to the 68030 bus as 
 * well as additional logic for interfacing with the 68882 FPU.
 *****************************************************************************/

module paste {
    inout wire          ncpuReset,          // 68030 reset signal (tristate)
    inout wire          ncpuHalt,           // 68030 halt signal (tristate)
    input wire          ncpuDS,             // 68030 data strobe signal
    output wire         ncpuDsack0,         // 68030 DS Ack 0 signal
    output wire         ncpuDsack1,         // 68030 DS Ack 1 signal
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
    input wire          npdsReset,          // PDS Reset signal
    inout wire          npdsLds,            // PDS Lower Data Strobe signal
    inout wire          npdsUds,            // PDS Upper Data Strobe signal
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
};

// define state machine states
parameter
    S0  =   2'h0,
    S1  =   2'h1,
    S2  =   2'h2;

// state machine state variables
logic [1:0] vmagenState;        // state machine for npdsVma generator
logic [1:0] dsack68genState;    // state machine for nDsack68 generator
logic [1:0] dsackSEgenState;    // state machine for nDsackSE generator
logic [1:0] resetgenState;      // state machine for nCpuReset generator

logic [3:0] vmagenCount;        // state counter for npdsVma generator

// intermediate signals
wire nDsack68;                  // 6800 bus termination signal
wire nDsackSE;                  // SE bus termination signal
wire nUD;                       // SE upper data byte select
wire nLD;                       // SE lower data byte select

// state machine for npdsVma generation
always @(posedge pdsC8m or negedge npdsReset) begin
    // sync state machine clocked by 8MHz system clock with async reset
    if(npdsReset == 1'b0) begin
        vmagenState <= S0;
        vmagenCount <= 4'h0;
    end else begin
        case(vmagenState)
            S0 : begin
                // wait for 6800 bus cycle to begin
                // marked by assertion of npdsVpa and pdsClockE
                if (npdsVpa == 1'b0 && pdsClockE == 1'b1) begin
                    vmagenState <= S1;
                else
                    vmagenState <= S0;
                end
                vmagenCount <= 4'h0;
            end
            S1 : begin
                // wait for deassertion of pdsClockE
                if (pdsClockE == 1'b0) begin
                    vmagenState <= S2;
                else
                    vmagenState <= S1;
                end
                vmagenCount <= 4'h0;
            end
            S2 : begin
                // increment vmagenCount until == 4'hA
                if (vmagenCount == 4'hA) begin
                    vmagenState <= S0;
                    vmagenCount <= 4'h0;
                else
                    vmagenState <= S2;
                    vmagenCount <= vmagenCount + 1'b1;
                end
            end
            default: begin
                // how did we end up here? reset to S0
                vmagenState <= S0;
                vmagenCount <= 4'h0;
            end
        endcase
    end
end

// state machine for nDsack68 generation
always @(posedge cpuClock or negedge npdsReset) begin
    // sync state machine clocked by primary CPU clock with async reset
    if(npdsReset == 1'b0) begin
        dsack68genState <= S0;
    end else begin
        case(dsack68genState)
            S0 : begin
                // wait for vmagenCount == 4'hA
                if (vmagenCount == 4'hA) begin
                    dsack68genState <= S1;
                else
                    dsack68genState <= S0;
                end
            end
            S1 : begin
                // immediately progress to S2
                dsack68genState <= S2;
            end
            S2 : begin
                // wait for vmagenCount to reset to 0
                if (vmagenCount == 4'h0) begin
                    dsack68genState <= S0;
                else
                    dsack68genState <= S2;
                end
            end
            default: begin
                // shouldn't be here. reset to S0
                dsack68genState <= S0;
            end
        endcase
    end
end

// state machine for nDsackSE generation
always @(posedge cpuClock or negedge npdsReset) begin
    // sync state machine clocked by primary CPU clock with async reset
    if(npdsReset == 1'b0) begin
        dsackSEgenState <= S0;
    end else begin
        case(dsackSEgenState)
            S0 : begin
                // wait for assertion of npdsDtack
                if(npdsDtack == 1'b0) begin
                    dsackSEgenState <= S1;
                else
                    dsackSEgenState <= S0;
                end
            end
            S1 : begin
                // immediately proceed to S3
                dsackSEgenState <= S2;
            end
            S2 : begin
                // wait for deassertion of npdsDtack
                if (npdsDtack == 1'b1) begin
                    dsackSEgenState <= S0;
                else
                    dsackSEgenState <= S2;
                end
            end
            default: begin
                // shouldn't be here. reset to S0
                dsackSEgenState <= S0;
            end
        endcase
    end
end

// state machine for power on reset
alwasy @(posedge cpuClock or negedge npdsReset) begin
    // sync state machine clocked by primary CPU clock with async reset
    if(npdsReset == 1'b0) begin
        resetgenState <= S0;
    end else begin
        case(resetgenState)
            S0 : begin
                // wait for deassertion of npdsReset
                if(npdsReset == 1'b1) begin
                    resetgenState <= S1;
                else
                    // shouldn't actually end up here
                    resetgenState <= S0;
                end
            end
            S1 : begin
                // wait for Bus Grant from SE
                if(npdsBg == 1'b0) begin
                    resetgenState <= S2;
                else
                    resetgenState <= S1;
                end
            end
            S2 : begin
                // this is actually our idle state.
                // stay here until the system resets again.
                if(npdsReset == 1'b1) begin
                    resetgenState <= S2;
                else
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

// and finally, our combinatorial logic
always_comb begin
    // DSACK intermediary signals
    if(dsack68genState == S1) begin
        nDsack68 <= 1'b0;
    else
        nDsack68 <= 1'b1;
    end
    if(dsackSEgenState == S1) begin
        nDsackSE <= 1'b0;
    else
        nDsackSE <= 1'b1;
    end

    // Upper/Lower data byte intermediary signals
    if(~cpuA0 || cpuRnW) begin
        nUD <= 1'b0;
    else
        nUD <= 1'b1;
    end
    if(cpuA0 || ~cpuSize0 || cpuSize1 || cpuRnW) begin
        nLD <= 1'b0;
    else
        nLD <= 1'b1;
    end

    // Upper/Lower data strobes
    if(~ncpuDS || ~nUD) begin
        npdsUds <= 1'b0;
    else
        npdsUds <= 1'bZ;
    end
    if(~ncpuDS || ~nLD) begin
        npdsLds <= 1'b0;
    else
        npdsLds <= 1'bZ;
    end

    // buffer enable signals
    if(ncpuBG == 1'b1) begin
        if(~nUD || ~npdsBg) begin
            nbufDhiEn <= 1'b0;
        else
            nbufDhiEn <= 1'b1;
        end
        if(~nLD || nUD || ~npdsBg) begin
            nbufDlo2En <= 1'b0;
        else
            nbufDlo2En <= 1'b1;
        end
        if(~nLD || ~nUD || ~npdsBg) begin
            nbufDlo1En <= 1'b0;
        else
            nbufDlo1En <= 1'b1;
        end
        if(npdsBg <= 1'b0) begin
            nbufAEn <= 1'b0;
            nbufCEn <= 1'b0;
        else
            nbufAEn <= 1'b1;
            nbufCEn <= 1'b1;
        end
    else
        nbufDhiEn <= 1'b1;
        nbufDlo2En <= 1'b1;
        nbufDlo1En <= 1'b1;
        nbufAEn <= 1'b1;
        nbufCEn <= 1'b1;
    end
    
    // data buffer direction
    bufDDir <= cpuRnW;

    // autovector request
    if(cpuFC == 3'h7 && nDsack68 == 1'b0) begin
        ncpuAvec <= 1'b0;
    else 
        ncpuAvec <= 1'b1;
    end

    // VMA signal
    if(vmagenCount >= 4'h3) begin
        npdsVma <= 1'b0;
    else
        npdsVma <= 1'bz;
    end

    // DS Ack signals
    if((nDsack68 == 1'b0 || (nDsackSE == 1'b0 && cpuAddrHi < 4'h5)) && cpuFC < 3'h7) begin
        ncpuDsack0 <= 1'b0;
    else
        ncpuDsack1 <= 1'b1;
    end
    if(nDsackSE == 1'b0 && cpuAddrHi >= 4'h5 && cpuFC < 3'h7) begin
        ncpuDsack1 <= 1'b0;
    else
        ncpuDsack1 <= 1'b1;
    end

    // CPU reset signals
    if(resetgenState == S2) begin
        ncpuReset <= 1'b0;
        ncpuHalt <= 1'b0;
    else
        ncpuReset <= 1'bz;
        ncpuHalt <= 1'bz;
    end

    // bus request & grant
    if(resetgenState == S0) begin
        npdsBr <= 1'bz;
    else
        npdsbr <= 1'b0;
    end
    if(resetgenState == S2) begin
        npdsBGack <= 1'b0;
    else
        npdsBGack <= 1'bz;
    end

    // FPU chip enable & presence detect
    if(cpuAddrMid == 7'h11 && cpuFC == 3'h7) begin
        nfpuCe <= 1'b0;
        if(nfpuSense == 1'b1) begin
            // pulled high means FPU missing. assert bus error
            ncpuBerr <= 1'b0;
        else
            ncpuBerr <= 1'bz;
        end
    else
        nfpuCe <= 1'b1;
        ncpuBerr <= 1'bz;
    end
end