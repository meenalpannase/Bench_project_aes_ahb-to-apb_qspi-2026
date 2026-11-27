`timescale 1ns/1ps

// Comprehensive end-to-end regression for aes128_cdc_top.
// "Exhaustive" here means exhaustive coverage of the implemented interfaces
// and important corner cases; it cannot mean all 2^128 AES input blocks.
module tb_aes128_cdc_top;

  localparam [5:0] KEY0=6'h00, KEY1=6'h04, KEY2=6'h08, KEY3=6'h0c;
  localparam [5:0] PT0 =6'h10, PT1 =6'h14, PT2 =6'h18, PT3 =6'h1c;
  localparam [5:0] CT0 =6'h20, CT1 =6'h24, CT2 =6'h28, CT3 =6'h2c;
  localparam [5:0] CTRL=6'h30, STATUS=6'h34, SEC=6'h38;

  reg pclk, presetn;
  reg [5:0] paddr;
  reg psel, penable, pwrite;
  reg [31:0] pwdata;
  reg [3:0] pstrb;
  reg [2:0] pprot;
  wire [31:0] prdata;
  wire pready, pslverr;

  reg crypto_clk, crypto_rst_n;

  integer pass_count, fail_count;
  integer i;
  reg [31:0] rdata;
  reg apb_err;
  reg [127:0] got_ct;

  aes128_cdc_top dut (
    .pclk(pclk), .presetn(presetn), .paddr(paddr), .psel(psel),
    .penable(penable), .pwrite(pwrite), .pwdata(pwdata), .pstrb(pstrb),
    .pprot(pprot), .prdata(prdata), .pready(pready), .pslverr(pslverr),
    .crypto_clk(crypto_clk), .crypto_rst_n(crypto_rst_n)
  );

  initial begin pclk=0; forever #5 pclk=~pclk; end
  initial begin crypto_clk=0; #2; forever #3.5 crypto_clk=~crypto_clk; end

  task check32;
    input [31:0] a, e; input [8*64-1:0] name;
    begin if(a===e) begin $display("PASS %-64s = %08h",name,a); pass_count=pass_count+1; end
      else begin $display("FAIL %-64s EXP=%08h GOT=%08h",name,e,a); fail_count=fail_count+1; end end
  endtask

  task check128;
    input [127:0] a, e; input [8*64-1:0] name;
    begin if(a===e) begin $display("PASS %-64s = %032h",name,a); pass_count=pass_count+1; end
      else begin $display("FAIL %-64s\n      EXP=%032h\n      GOT=%032h",name,e,a); fail_count=fail_count+1; end end
  endtask

  task apb_write;
    input [5:0] addr; input [31:0] data; input [3:0] strb; input [2:0] prot;
    begin
      @(posedge pclk); paddr<=addr; pwdata<=data; pstrb<=strb; pprot<=prot;
      pwrite<=1; psel<=1; penable<=0;
      @(posedge pclk); penable<=1; #1; apb_err=pslverr;
      @(posedge pclk); psel<=0; penable<=0; pwrite<=0; paddr<=0; pwdata<=0; pstrb<=0; pprot<=0;
    end
  endtask

  task apb_read;
    input [5:0] addr; input [2:0] prot; output [31:0] data;
    begin
      @(posedge pclk); paddr<=addr; pprot<=prot; pwrite<=0; psel<=1; penable<=0;
      @(posedge pclk); penable<=1; #1; data=prdata; apb_err=pslverr;
      @(posedge pclk); psel<=0; penable<=0; paddr<=0; pprot<=0;
    end
  endtask

  task write_key_pt;
    input [127:0] key, pt;
    begin
      apb_write(KEY0,key[31:0],4'hf,3'b001);
      apb_write(KEY1,key[63:32],4'hf,3'b001);
      apb_write(KEY2,key[95:64],4'hf,3'b001);
      apb_write(KEY3,key[127:96],4'hf,3'b001);
      apb_write(PT0,pt[31:0],4'hf,3'b001);
      apb_write(PT1,pt[63:32],4'hf,3'b001);
      apb_write(PT2,pt[95:64],4'hf,3'b001);
      apb_write(PT3,pt[127:96],4'hf,3'b001);
    end
  endtask

  task wait_done;
    reg [31:0] s; integer n;
    begin
      s=0;
      for(n=0;n<3000;n=n+1) begin
        apb_read(STATUS,3'b001,s);
        if(s[0]===1'b1) n=3000;
      end
      if(s[0]!==1'b1) begin $display("FAIL DONE timeout"); fail_count=fail_count+1; end
    end
  endtask

  task read_ct;
    output [127:0] ct; reg [31:0] a,b,c,d;
    begin
      apb_read(CT0,3'b001,a); apb_read(CT1,3'b001,b);
      apb_read(CT2,3'b001,c); apb_read(CT3,3'b001,d);
      ct={d,c,b,a};
    end
  endtask

  task kat;
    input [127:0] key,pt,exp; input [8*64-1:0] name;
    begin
      write_key_pt(key,pt); apb_write(CTRL,32'h1,4'b0001,3'b001);
      wait_done; read_ct(got_ct); check128(got_ct,exp,name);
    end
  endtask

  task zeroize;
    begin
      apb_write(SEC,32'h2,4'b0001,3'b001);
      repeat(8) @(posedge crypto_clk); repeat(3) @(posedge pclk);
    end
  endtask

  initial begin
    pass_count=0; fail_count=0;
    paddr=0; psel=0; penable=0; pwrite=0; pwdata=0; pstrb=0; pprot=0;
    presetn=0; crypto_rst_n=0;
    repeat(5) @(posedge pclk); presetn=1;
    repeat(4) @(posedge crypto_clk); crypto_rst_n=1;
    repeat(4) @(posedge pclk);

    $display("==============================================================");
    $display("AES-128 APB/CDC COMPREHENSIVE REGRESSION");
    $display("==============================================================");

    // Reset/status.
    apb_read(STATUS,3'b001,rdata); check32(rdata,0,"STATUS reset");
    apb_read(SEC,3'b001,rdata);    check32(rdata,0,"SECURITY reset");

    // FIPS-197 and standard AES-128 KATs.
    kat(128'h000102030405060708090a0b0c0d0e0f,
        128'h00112233445566778899aabbccddeeff,
        128'h69c4e0d86a7b0430d8cdb78070b4c55a,"FIPS-197 AES-128");
    kat(128'h00000000000000000000000000000000,
        128'h00000000000000000000000000000000,
        128'h66e94bd4ef8a2c3b884cfa59ca342b2e,"AES-128 zero/zero");
    kat(128'hffffffffffffffffffffffffffffffff,
        128'hffffffffffffffffffffffffffffffff,
        128'hbcbf217cb280cf30b2517052193ab979,"AES-128 FF/FF");

    // NIST SP 800-38A AES-128 ECB vectors.
    kat(128'h2b7e151628aed2a6abf7158809cf4f3c,
        128'h6bc1bee22e409f96e93d7e117393172a,
        128'h3ad77bb40d7a3660a89ecaf32466ef97,"NIST ECB block 1");
    kat(128'h2b7e151628aed2a6abf7158809cf4f3c,
        128'hae2d8a571e03ac9c9eb76fac45af8e51,
        128'hf5d3d58503b9699de785895a96fdbaaf,"NIST ECB block 2");
    kat(128'h2b7e151628aed2a6abf7158809cf4f3c,
        128'h30c81c46a35ce411e5fbc1191a0a52ef,
        128'h43b1cd7f598ece23881b00e3ed030688,"NIST ECB block 3");
    kat(128'h2b7e151628aed2a6abf7158809cf4f3c,
        128'hf69f2445df4f9b17ad2b417be66c3710,
        128'h7b0c785e27e8ad3f8223207104725dd4,"NIST ECB block 4");

    // Key read protection.
    apb_read(KEY0,3'b001,rdata); check32(rdata,0,"KEY0 read protected");
    apb_read(KEY1,3'b001,rdata); check32(rdata,0,"KEY1 read protected");
    apb_read(KEY2,3'b001,rdata); check32(rdata,0,"KEY2 read protected");
    apb_read(KEY3,3'b001,rdata); check32(rdata,0,"KEY3 read protected");

    // Non-privileged security access must error.
    apb_write(KEY0,32'hdeadbeef,4'hf,3'b000);
    if(apb_err) begin $display("PASS nonprivileged KEY write rejected"); pass_count=pass_count+1; end
    else begin $display("FAIL nonprivileged KEY write accepted"); fail_count=fail_count+1; end
    apb_write(SEC,32'h1,4'b0001,3'b000);
    if(apb_err) begin $display("PASS nonprivileged SECURITY write rejected"); pass_count=pass_count+1; end
    else begin $display("FAIL nonprivileged SECURITY write accepted"); fail_count=fail_count+1; end
    apb_read(STATUS,3'b001,rdata);
    if(rdata[2]) begin $display("PASS sticky security violation"); pass_count=pass_count+1; end
    else begin $display("FAIL sticky security violation"); fail_count=fail_count+1; end

    // Key lock and sticky behavior.
    zeroize;
    // reset crypto too for a clean FIFO state after zeroize.
    crypto_rst_n=0; repeat(3) @(posedge crypto_clk); crypto_rst_n=1; repeat(3) @(posedge crypto_clk);
    apb_write(SEC,32'h1,4'b0001,3'b001);
    apb_read(SEC,3'b001,rdata); check32(rdata,32'h1,"KEY_LOCK set");
    apb_write(KEY0,32'h12345678,4'hf,3'b001);
    if(apb_err) begin $display("PASS locked KEY write rejected"); pass_count=pass_count+1; end
    else begin $display("FAIL locked KEY write accepted"); fail_count=fail_count+1; end
    zeroize;
    apb_read(SEC,3'b001,rdata); check32(rdata,32'h1,"KEY_LOCK survives zeroize");

    // APB reset clears sticky security state and key lock.
    @(posedge pclk); presetn=0; repeat(3) @(posedge pclk); presetn=1; repeat(3) @(posedge pclk);
    apb_read(SEC,3'b001,rdata); check32(rdata,0,"SECURITY after reset");
    apb_read(STATUS,3'b001,rdata); check32(rdata,0,"STATUS after reset");
    crypto_rst_n=0; repeat(3) @(posedge crypto_clk); crypto_rst_n=1; repeat(3) @(posedge crypto_clk);

    // Four queued commands: command FIFO depth is 4.
    write_key_pt(128'h000102030405060708090a0b0c0d0e0f,128'h00112233445566778899aabbccddeeff);
    apb_write(CTRL,1,4'b0001,3'b001);
    write_key_pt(128'h000102030405060708090a0b0c0d0e0f,128'h00000000000000000000000000000000);
    apb_write(CTRL,1,4'b0001,3'b001);
    write_key_pt(128'h2b7e151628aed2a6abf7158809cf4f3c,128'h6bc1bee22e409f96e93d7e117393172a);
    apb_write(CTRL,1,4'b0001,3'b001);
    write_key_pt(128'h2b7e151628aed2a6abf7158809cf4f3c,128'hae2d8a571e03ac9c9eb76fac45af8e51);
    apb_write(CTRL,1,4'b0001,3'b001);

    wait_done; read_ct(got_ct); check128(got_ct,128'h69c4e0d86a7b0430d8cdb78070b4c55a,"queued result 1");
    wait_done; read_ct(got_ct); check128(got_ct,128'hc6a13b37878f5b826f4f8162a1c8d879,"queued result 2");
    wait_done; read_ct(got_ct); check128(got_ct,128'h3ad77bb40d7a3660a89ecaf32466ef97,"queued result 3");
    wait_done; read_ct(got_ct); check128(got_ct,128'hf5d3d58503b9699de785895a96fdbaaf,"queued result 4");

    // Zeroization clears software-visible PT/CT state.
    zeroize;
    apb_read(PT0,3'b001,rdata); check32(rdata,0,"PT0 zeroized");
    apb_read(PT1,3'b001,rdata); check32(rdata,0,"PT1 zeroized");
    apb_read(PT2,3'b001,rdata); check32(rdata,0,"PT2 zeroized");
    apb_read(PT3,3'b001,rdata); check32(rdata,0,"PT3 zeroized");
    apb_read(CT0,3'b001,rdata); check32(rdata,0,"CT0 zeroized");
    apb_read(CT1,3'b001,rdata); check32(rdata,0,"CT1 zeroized");
    apb_read(CT2,3'b001,rdata); check32(rdata,0,"CT2 zeroized");
    apb_read(CT3,3'b001,rdata); check32(rdata,0,"CT3 zeroized");

    // Invalid address.
    apb_write(6'h3c,32'h12345678,4'hf,3'b001);
    if(apb_err) begin $display("PASS invalid APB write rejected"); pass_count=pass_count+1; end
    else begin $display("FAIL invalid APB write accepted"); fail_count=fail_count+1; end
    apb_read(6'h3c,3'b001,rdata);
    if(apb_err) begin $display("PASS invalid APB read rejected"); pass_count=pass_count+1; end
    else begin $display("FAIL invalid APB read accepted"); fail_count=fail_count+1; end

    // PSTRB functional verification.
    //
    // PT registers are intentionally write-only, so the merged PT0 value
    // cannot be verified by reading PT0. Verify it through AES instead:
    //
    //   PT0 full write : AABBCCDD
    //   PT0 low bytes  : 00001122 with PSTRB=0011
    //   Final plaintext: AABB1122000000000000000000000000
    //
    // With key 2b7e151628aed2a6abf7158809cf4f3c, the expected ciphertext is
    // f9fc0e9b47aceb1a03f5492f9abc3df9.
    apb_write(PT0,32'hAABBCCDD,4'hf,3'b001);
    apb_write(PT0,32'h00001122,4'b0011,3'b001);
    apb_write(PT1,32'h00000000,4'hf,3'b001);
    apb_write(PT2,32'h00000000,4'hf,3'b001);
    apb_write(PT3,32'h00000000,4'hf,3'b001);

    // Key used for the PSTRB functional check.
    apb_write(KEY0,32'h09cf4f3c,4'hf,3'b001);
    apb_write(KEY1,32'habf71588,4'hf,3'b001);
    apb_write(KEY2,32'h28aed2a6,4'hf,3'b001);
    apb_write(KEY3,32'h2b7e1516,4'hf,3'b001);

    apb_write(CTRL,32'h00000001,4'b0001,3'b001);
    wait_done;
    read_ct(got_ct);
    check128(
      got_ct,
      128'hf9fc0e9b47aceb1a03f5492f9abc3df9,
      "PSTRB functional merge"
    );


    $display("==============================================================");
    $display("PASS=%0d FAIL=%0d",pass_count,fail_count);
    if(fail_count==0) $display("*** ALL TESTS PASSED ***");
    else              $display("*** FAILURES PRESENT - DO NOT SUBMIT ***");
    $display("==============================================================");
    #100 $finish;
  end

  initial begin
    #2_000_000;
    $display("FATAL: global timeout");
    $finish;
  end

  initial begin
    $dumpfile("waveform.vcd");
    $dumpvars(0,tb_aes128_cdc_top);
    end

endmodule