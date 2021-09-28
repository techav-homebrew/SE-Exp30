/******************************************************************************
 * SE-Exp30 MacSE Accelerator
 * techav
 * 2021-09-26
 * Processor Accelerator System Translation Engine
 ******************************************************************************
 * Handles all logic to translate the Mac SE 68000 PDS bus to the 68030 bus as 
 * well as additional logic for interfacing with the 68882 FPU.
 *****************************************************************************/

module paste (
    inout wire          cpuRESETnz,         // 68030 reset signal (tristate)
    inout wire          cpuHALTnz,          // 68030 halt signal (tristate)
    input wire          cpuDSn,             // 68030 data strobe signal
    input wire          cpuASn,             // 68030 address strobe signal
    inout wire          cpuDSACK0nz,        // 68030 DS Ack 0 signal
    inout wire          cpuDSACK1nz,        // 68030 DS Ack 1 signal
    input wire          cpuSIZE0,           // 68030 Size 0 signal
    input wire          cpuSIZE1,           // 68030 Size 1 signal
    input wire          cpuA0,              // 68030 Address 0 signal
    input logic [3:0]   cpuAHI,             // 68030 Address Hi (16MB) signals A[23:20]
    input logic [6:0]   cpuAMID,            // 68030 Address Mid (FPU decode) signals A[19:13]
    output wire         cpuAVECn,           // 68030 Autovector request signal
    input logic [2:0]   cpuFC,              // 68030 Function Code signals
    input wire          cpuClock,           // 68030 Primary CPU Clock signal
    input wire          cpuRnW,             // 68030 Read/Write signal
    input wire          cpuBGn,             // 68030 Bus Grant signal
    output wire         cpuBERRn,           // 68030 Bus Error signal
    output wire         cpuCIINn,           // 68030 Cache Inhibit signal
    input wire          pdsRESETn,          // PDS Reset signal
    inout wire          pdsLDSnz,           // PDS Lower Data Strobe signal
    inout wire          pdsUDSnz,           // PDS Upper Data Strobe signal
    inout wire          pdsASnz,            // PDS Address Strobe signal
    input wire          pdsDTACKn,          // PDS Data Xfer Ack signal
    input wire          pdsBGn,             // PDS Bus Grant signal
    output wire         pdsBGACKn,          // PDS Bus Grant Ack signal
    output wire         pdsBRn,             // PDS Bus Request signal
    inout wire          pdsVMAnz,           // PDS Valid Memory Addr signal
    input wire          pdsVPAn,            // PDS Valid Peripheral Addr signal
    input wire          pdsBERRn,           // PDS Bus Error signal
    input wire          pdsC8M,             // PDS 8MHz System Clock signal
    output wire         pdsClockE,          // PDS 800kHz 6800 bus E clock
    output wire         bufDHICEn,          // Data buffer CPU[31:24] <=> PDS[15:8]
    output wire         bufDLO1CEn,         // Data buffer CPU[23:16] <=> PDS[7:0]
    output wire         bufDLO2CEn,         // Data buffer CPU[31:24] <=> PDS[7:0]
    output wire         bufDDIR,            // Data buffer direction
    output wire         bufCCEn,            // Control signal buffer enable
    output wire         bufACEn,            // Address buffer enable
    input wire          fpuSENSEn,          // FPU Presence Detect signal
    output wire         fpuCEn              // FPU Chip Select signal
);

// pds address strobe
logic pdsASnINNER;
always @(posedge pdsC8M or posedge cpuASn) begin
    if(cpuASn) pdsASnINNER <= 1;
    else if(pdsC8M && !cpuASn) pdsASnINNER <= 0;
    else pdsASnINNER <= 1;
end
always_comb begin
    if(pdsBGn) pdsASnz <= 1'bZ;
    else if(!pdsASnINNER) pdsASnz <= 0;
    else pdsASnz <= 1'bZ;
end

// cpu bus termination (normal, 6800, & autovector)
logic cpuDTACKnINNER;
always @(posedge pdsC8M or posedge cpuASn) begin
    if(cpuASn) cpuDTACKnINNER <= 1;
    else if(pdsC8M && !pdsASnINNER && !pdsDTACKn) cpuDTACKnINNER <= 0;
    else cpuDTACKnINNER <= 1;
end
always_comb begin
    if(cpuFC == 3'h7) begin
        // CPU space cycle
        if(!cpuDTACK68nINNER) begin
            // interrupt autovector
            cpuDSACK0nz <= 1'bZ;
            cpuDSACK1nz <= 1'bZ;
            cpuAVECn <= 0;
        end else begin
            // We shouldn't need anything else in CPU space
            cpuDSACK0nz <= 1'bZ;
            cpuDSACK1nz <= 1'bZ;
            cpuAVECn <= 1;
        end
    end else begin
        // normal memory or I/O cycle
        if(cpuAHI < 4'h4) begin
            // 16-bit RAM access cycle
            if(cpuDTACKnINNER) begin
                cpuDSACK0nz <= 1'bZ;
                cpuDSACK1nz <= 1'bZ;
                cpuAVECn <= 1;
            end else begin
                cpuDSACK0nz <= 1'bZ;
                cpuDSACK1nz <= 0;
                cpuAVECn <= 1;
            end
        end else begin
            if(!cpuDTACKnINNER || !cpuDTACK68nINNER) begin
                cpuDSACK0nz <= 0;
                cpuDSACK1nz <= 1'bZ;
                cpuAVECn <= 1;
            end else begin
                cpuDSACK0nz <= 1'bZ;
                cpuDSACK1nz <= 1'bZ;
                cpuAVECn <= 1;
            end
        end
    end
end

// pds E clock & 6800 bus
reg [3:0] pdsEcount;
reg pdsVMAnINNER, cpuDTACK68nINNER;
always @(posedge pdsC8M) begin
    if(pdsEcount == 9) pdsEcount <= 0;
    else pdsEcount <= pdsEcount + 4'h1;
end
always @(posedge cpuClock or posedge pdsVPAn) begin
    if(pdsVPAn) pdsVMAnINNER <= 1;
    else if(!pdsVPAn && pdsEcount == 2) pdsVMAnINNER <= 0;
end
always @(posedge pdsC8M or posedge cpuASn) begin
    if(cpuASn) cpuDTACK68nINNER <= 1;
    else if(!pdsVMAnINNER && pdsEcount > 8) cpuDTACK68nINNER <= 0;
end
always_comb begin
    if(pdsEcount < 6) pdsClockE <= 0;
    else pdsClockE <= 1;

    if(pdsVMAnINNER) pdsVMAnz <= 1'bZ;
    else pdsVMAnz <= 0;
end

// pds data strobes
reg pdsDSnINNER;
wire pdsDSn2INNER;
wire pdsLDSnINNER;
wire pdsUDSnINNER;
always @(posedge pdsC8M or posedge cpuASn) begin
    if(cpuASn) pdsDSnINNER <= 1;
    else if (pdsC8M && !pdsASnINNER) pdsDSnINNER <= 0;
    else pdsDSnINNER <= 1;
end
always_comb begin
    if(cpuRnW) pdsDSn2INNER <= pdsASnINNER;
    else pdsDSn2INNER <= pdsDSnINNER;
    
    // Upper Data Strobe
    if(pdsDSn2INNER) begin
        pdsUDSnINNER <= 1;
    end else begin
        if(cpuRnW) begin
            // read
            pdsUDSnINNER <= 0;
        end else begin
            // write
            if(cpuA0) pdsUDSnINNER <= 1;
            else pdsUDSnINNER <= 0;
        end
    end

    // Lower Data Strobe
    if(pdsDSn2INNER) begin
        pdsLDSnINNER <= 1;
    end else begin
        if(cpuRnW) begin
            // read
            pdsLDSnINNER <= 0;
        end else begin
            // write
            if(cpuSIZE0 == 1 && cpuSIZE1 == 0 && cpuA0 == 0) pdsLDSnINNER <= 1;
            else pdsLDSnINNER <= 0;
        end
    end

    // Data Strobe outputs
    if(pdsBGn) begin
        pdsLDSnz <= 1'bZ;
        pdsUDSnz <= 1'bZ;
    end else begin
        if(pdsLDSnINNER) pdsLDSnz <= 1'bZ;
        else pdsLDSnz <= 0;
        if(pdsUDSnINNER) pdsUDSnz <= 1'bZ;
        else pdsUDSnz <= 0;
    end
end

// fpu addressing
wire fpuCEnINNER;
always_comb begin
    if(cpuAHI == 0 && cpuAMID == 7'h11 && cpuFC == 3'h7) fpuCEnINNER <= 0;
    else fpuCEnINNER <= 1;

    fpuCEn <= fpuCEnINNER;
end

// bus error
always_comb begin
    if(!fpuCEnINNER && !cpuASn && fpuSENSEn) cpuBERRn <= 0;
    else if(!pdsBERRn) cpuBERRn <= 0;
    else cpuBERRn <= 1;
end

// cache inhibit
always_comb begin
    if(cpuAHI >= 4'h4) cpuCIINn <= 0;
    else cpuCIINn <= 1;
end

// cpu reset
reg [1:0] resetState;
always @(posedge cpuClock or negedge pdsRESETn) begin
    if(!pdsRESETn) resetState <= 0;
    else if(cpuClock) begin
        case(resetState) 
            0: begin
                if(pdsRESETn) resetState <= 1;
                else resetState <= 0;
            end
            1: begin
                if(!pdsBGn) resetState <= 2;
                else resetState <= 1;
            end
            2: begin
                resetState <= 2;
            end
            default: begin
                resetState <= 2;
            end
        endcase
    end
end
always_comb begin
    if(resetState == 2) begin
        cpuHALTnz <= 1'bZ;
        cpuRESETnz <= 1'bZ;
        pdsBGACKn <= 0;
    end else begin
        cpuHALTnz <= 0;
        cpuRESETnz <= 0;
        pdsBGACKn <= 1;
    end
    pdsBRn <= 0;
end

// bus buffer controls
assign bufACEn = cpuASn;
assign bufCCEn = pdsBGn;
assign bufDDIR = cpuRnW;

wire siz, siza;
assign siz = cpuSIZE0 & ~cpuSIZE1;
assign bufDLO1CEn = siz | cpuDSn;
assign siza = siz & cpuA0;
assign bufDLO2CEn = ~siza | cpuDSn;
assign bufDHICEn = siza | cpuDSn;


endmodule