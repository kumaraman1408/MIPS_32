class transaction;
  typedef enum bit [1:0] {write=2'b00,read=2'b01} oper_type;
  randc oper_type oper;
  bit rx;
  rand bit [7:0] dintx;
  bit send;
  bit tx;
  bit [7:0] doutrx;
  bit donetx;
  bit donerx;
  function void display(input string tag);
  $display("[%0s]:oper:%0s send: %0b TX_DATA :%b RX_IN: %0b TX_out:%0b DONE_TX:%0b DONE_RX: 				%0b",tag,oper.name(),send,dintx,rx,tx,doutrx,donetx,donerx);
  endfunction
  function transaction copy();
    copy=new();
    copy.rx=this.rx;
    copy.dintx=this.dintx;
    copy.send=this.dintx;
    copy.tx=this.tx;
    copy.doutrx=this.doutrx;
    copy.donetx=this.donetx;
    copy.donerx=this.donerx;
    copy.oper=this.oper;
  endfunction
endclass
class generator;
  transaction tr;
  mailbox #(transaction) mbxgd;
  event done;
  event drvnext;
  event sconext;
  int count=0;
  function new(mailbox #(transaction) mbxgd);
    this.mbxgd=mbxgd;
    tr=new();
  endfunction
  task run();
    repeat(count)
      begin
        assert(tr.randomize) else $error("[GEN]:Randomization Failed");
        mbxgd.put(tr.copy);
        tr.display("GEN");
        @(drvnext);
        @(sconext);
      end
    ->done;
  endtask
endclass
class driver;
  virtual uart_if vif;
  transaction tr;
  mailbox #(transaction) mbxgd;
  mailbox #(bit [7:0]) mbxds;
  event drvnext;
  bit [7:0] datarx;
  function new( mailbox #(bit [7:0]) mbxds,mailbox #(transaction) mbxgd);
    this.mbxgd=mbxgd;
    this.mbxds=mbxds;
  endfunction
  task reset();
    vif.rst<=1'b1;
    vif.dintx<=0;
    vif.send<=0;
    vif.rx=1'b1;
    vif.doutrx<=0;
    vif.tx<=1'b1;
    vif.donerx<=0;
    vif.donetx<=0;
    repeat(5) @(posedge vif.uclktx);
    vif.rst<=1'b0;
    @(posedge vif.uclktx);
    $display("[DRV]:RESET DONE");
  endtask
  task run();
    forever begin
      mbxgd.get(tr); 
      if(tr.oper==2'b00)
        begin
          @(posedge vif.uclktx);
          vif.rst<=1'b0;
          vif.send<=1'b1;
          vif.rx<=1'b1;
          vif.dintx=tr.dintx;
          @(posedge vif.uclktx);
          vif.send<=1'b0;
          mbxds.put(tr.dintx);
          $display("[DRV]:Data Sent: %0d",tr.dintx); 
          wait(vif.donetx==1'b1);
          ->drvnext;
        end
      else if(tr.oper==2'b01)
      begin
        @(posedge vif.uclkrx);
        vif.rst<=1'b0;
        vif.rx<=1'b0;
        vif.send<=1'b0;
        @(posedge vif.uclkrx);
        for(int i=0;i<=7;i++)
          begin
            @(posedge vif.uclkrx);
            vif.rx<=$urandom;
            datarx[i]=vif.rx;
        end
        mbxds.put(datarx);
        $display("[DRV]:Data RCVD:%0d",datarx);
        wait(vif.donerx==1'b1);
        vif.rx<=1'b1;
        ->drvnext;
      end
    end
  endtask
endclass

class monitor;
  transaction tr;
  mailbox #(bit [7:0]) mbxms;
  bit [7:0] srx;
  bit [7:0] rrx;
  virtual uart_if vif;
  function new(mailbox #(bit [7:0]) mbxms);
    this.mbxms=mbxms;
  endfunction
  task run();
    forever begin
      @(posedge vif.uclktx);
      if((vif.send==1'b1) &&(vif.rx==1'b1))
        begin
          @(posedge vif.uclktx);
          for(int i=0;i<=7;i++)
            begin
              @(posedge vif.uclktx);
              srx[i]=vif.tx;
            end
          $display("[MON]:DATA SEND on UART TX %0d",srx);
          @(posedge vif.uclktx);
          mbxms.put(srx);
        end
      else if ((vif.rx==1'b0) &&(vif.send==1'b0))
      begin
        wait(vif.donerx==1);
        rrx=vif.doutrx;
        $display("[MON]:DATA RCVD RX %0d",rrx);
        @(posedge vif.uclktx);
        mbxms.put(rrx);
      end
    end
  endtask
endclass

class scoreboard;
  mailbox #(bit[7:0]) mbxds, mbxms;
 
  bit [7:0] ds;
  bit [7:0] ms;
  event sconext;
  function new(mailbox #(bit [7:0]) mbxds,mailbox #(bit[7:0]) mbxms);
    this.mbxds=mbxds;
    this.mbxms=mbxms;
  endfunction
  task run();
    forever begin
      mbxds.get(ds);
      mbxms.get(ms);
      $display("[SCO]:DRV: %0d MON:%0d",ds,ms);
      if(ds==ms)
        $display("DATA MATCHED");
      else
        $display("DATA MISMATCHED");
      ->sconext;
    end
  endtask
endclass


class environment;
  generator gen;
  driver drv;
  monitor mon;
  scoreboard sco;
  event nextgd;
  event nextgs;
  mailbox #(transaction) mbxgd;
  mailbox #(bit[7:0]) mbxds;
  mailbox #(bit [7:0]) mbxms; 
  virtual uart_if vif;
  
  function new (virtual uart_if vif);
    mbxgd=new();
    mbxms=new();
    mbxds=new();
    gen=new(mbxgd);
    drv=new(mbxds,mbxgd);
    mon=new(mbxms);
    sco=new(mbxds,mbxms); 
    this.vif=vif;
    drv.vif=this.vif;
    mon.vif=this.vif;
    gen.sconext=nextgs;
    sco.sconext=nextgs;
    gen.drvnext=nextgd;
    drv.drvnext=nextgd;
  endfunction
 
  task pre_test();
    drv.reset();
  endtask
  //test
  task test();
    fork
      gen.run();
      drv.run();
      mon.run();
      sco.run();
    join_any
  endtask
  task post_test();
    wait(gen.done.triggered);
    $finish();
  endtask
  task run();
    pre_test();
    test();
    post_test();
  endtask
endclass

module tb;
  uart_if vif();
  uart_top#(1000000,9600) dut (vif.clk,vif.rst,vif.rx,vif.dintx,vif.send,vif.tx,vif.doutrx,vif.donetx,vif.donerx);
  initial begin
    vif.clk<=0;
  end
  always #10 vif.clk<= ~vif.clk;
  environment env;
  initial begin
    env=new(vif);
    env.gen.count=5;
    env.run();
  end
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end
  assign vif.uclktx=dut.utx.uclk;
  assign vif.uclkrx=dut.rtx.uclk;
endmodule

    
    
        
  
  
  
