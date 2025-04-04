

// todo: find a better name
module dragoncoco(
  input clk, // 57.272727 mhz
  input turbo,
  input trig_reset_n, // todo: reset_n doesn't work!  // done. CPU needs reset low for 2 full cpu cycles (that's 128 clk cycles) with the clocks running.
							 // which means that reset of SAM needs to Be released far before the cpu reset_n goes inactive
  input hard_reset,
  input dragon,
  input dragon64,
  input kblayout,

  // video signals
  output [7:0] red,
  output [7:0] green,
  output [7:0] blue,

  output hblank,
  output vblank,
  output hsync,
  output vsync,
  
  // clocks output
  output vclk,
  output clk_Q_out,

  // video options
  input artifact_phase,
  input artifact_enable,
  input overscan,


  input uart_din,  // not connected yet

  // keyboard
  input [10:0] ps2_key,

  // joystick input
  // digital for buttons
  input [15:0] joy1,  
  input [15:0] joy2,
  // analog for position
  input [15:0] joya1,
  input [15:0] joya2,
  input joy_use_dpad,

  
  // roms, cartridges, etc
  input [7:0] ioctl_data,
  input [15:0] ioctl_addr,
  input ioctl_download,
  input ioctl_wr,
  input [15:0] ioctl_index,
  output [3:0] roms_loaded,
  input roms_reset,


  // cassette signals
  input casdout,
  output cas_relay,
  
  // sound
  input [11:0] cass_snd,
  output [11:0] sound,
  output sndout,
  
  // debug for video overlay
  output [8:0] v_count,
  output [8:0] h_count,
  output [159:0] DLine1,
  output [159:0] DLine2,


  // DISK
  //
  input disk_cart_enabled,
  input				CLK50MHZ,

  // SD block level interface
  input   [4:0]  		img_mounted, // signaling that new image has been mounted
  input				img_readonly, // mounted as read only. valid only for active bit in img_mounted
  input 	[19:0] 		img_size,    // size of image in bytes. 1MB MAX!

  output	[31:0] 		sd_lba[5],
  output  [5:0] 		sd_blk_cnt[5], // number of blocks-1, total size ((sd_blk_cnt+1)*(1<<(BLKSZ+7))) must be <= 16384!

  output 	reg  [4:0]	sd_rd,
  output 	reg  [4:0]	sd_wr,
  input        [4:0]	sd_ack,

  // SD byte level access. Signals for 2-PORT altsyncram.
  input  	[8:0] 		sd_buff_addr,
  input  	[7:0] 		sd_buff_dout,
  output 	[7:0] 		sd_buff_din[5],
  input        			sd_buff_wr,

  input					CASS_REWIND_RECORD
);


shortint reset_counter ;
wire reset_n, l_reset ;

assign l_reset = ~trig_reset_n || hard_reset || (disk_cart_enabled ^ disk_cart_enabled_d );

always @(posedge clk or posedge l_reset)
begin
	if (l_reset)
	begin
		reset_counter <= 256 ;  // minimum 1 cycle at low speed = 64 clk
		reset_n <= 1'b0 ;
	end 
	else begin 
			if (reset_counter != 0) reset_counter<=reset_counter-1 ; else reset_n <= 1'b1 ;
	end
end

assign clk_Q_out = clk_Q;
wire clk_enable ;

wire nmi; 
wire halt; 

wire clk_E, clk_Q;


wire [7:0] cpu_dout;
wire [15:0] cpu_addr;
wire cpu_rw;
wire cpu_bs;
wire cpu_ba;
wire cpu_adv_valid_addr;
wire cpu_busy;
wire cpu_last_inst_cycle;
wire irq;
wire firq;
wire cart_firq;

wire ram_cs,rom8_cs,rom8k_cs,romA_cs,romC_cs,io_cs,pia1_cs,pia_cs,pia_orig_cs;


wire [7:0]vdg_data;
reg [7:0] ram_dout;
reg [7:0] ram_dout_b;
wire [7:0] rom8_dout;
reg [7:0] rom8_dout2;
// wire [7:0] romA_dout;
// reg [7:0] romA_dout2;
wire [7:0] romC_dout;
wire [7:0] romC_cart_dout;
wire [7:0] romC_disk_dout;
wire [7:0] romC_dragondisk_dout;
reg [7:0] romC_dout2;
wire [7:0] pia_dout;
reg [7:0] pia_dout2;
wire [7:0] pia1_dout;
reg [7:0] pia1_dout2;
wire [7:0] io_out;

wire we = ~cpu_rw & clk_E;


wire [7:0] keyboard_data;
wire [7:0] kb_cols, kb_rows;

wire [7:0] pia1_portb_out;

// data mux

wire [7:0] cpu_din;

// always @(posedge clk)
always_comb begin
   unique case (1'b1)
     ram_cs:  cpu_din =  ram_dout;
     rom8_cs: cpu_din =  rom8_dout2;
     romA_cs: cpu_din =  rom8_dout2;  // rom8 is now 16K, from 0x8000 to 0xBFFF
     romC_cs: cpu_din =  romC_dout2;
     pia_cs:  cpu_din =  pia_dout2;
     pia1_cs: cpu_din =  pia1_dout2;
     io_cs:   cpu_din =  io_out;
     default: cpu_din =  8'hff;
   endcase
	
end


/*
Dragon 64 has two hardware changes to access more I/O

cpu_addr[2] is used as a select between the pia and the ACIA serial

pia_portb_out[2] switches between the rom and alternative rom chip
*/


assign pia_cs = dragon64 ? pia_64_cs : pia_orig_cs ;             

wire pia_64_cs= ~cpu_addr[2] & pia_orig_cs;
wire acia_cs = cpu_addr[2] &  pia_orig_cs ;

/* because of the tristate nature of the real hardware, and one pin having a resistor
   pulling it high, we wired the output of DDRB2 to this logic, and it seems to swap 
	ROM banks correctly now. A bit of a hack, but it seems to work.
*/
wire [7:0] cpu_din64;

always_comb begin
   unique case (1'b1)
     ram_cs:     cpu_din64 =  ram_dout;
     rom8_cs:    cpu_din64 =  rom8_64_1_2 ;
     romC_cs:    cpu_din64 =  romC_dout2;
	  acia_cs:    cpu_din64 =  acia_dout;
     pia_cs:     cpu_din64 =  pia_dout2;
     pia1_cs:    cpu_din64 =  pia1_dout2;
     io_cs:      cpu_din64 =  io_out;
     default:    cpu_din64 =  8'hff;
   endcase
end

mc6809i cpu(
  .clk(clk),
  .D(dragon64?cpu_din64:cpu_din),
  .DOut(cpu_dout),
  .ADDR(cpu_addr),
  .RnW(cpu_rw),
  .E(clk_E),
  .Q(clk_Q),
  .BS(cpu_bs),
  .BA(cpu_ba),
  .nIRQ(~irq),
  .nFIRQ(~firq),
  .nNMI(~nmi),
  .AVMA(cpu_adv_valid_addr),
  .BUSY(cpu_busy),
  .LIC(cpu_last_inst_cycle),
  //.nHALT(dragon ? 1'b1 : ~halt),
  .nHALT(~halt),
  .nRESET(reset_n),
  .nDMABREQ(1)
);



dpram #(.addr_width_g(16), .data_width_g(8)) ram1(
  .clock_a(clk),
  .address_a(cpu_addr),
  .data_a(cpu_dout),
  .q_a(/*ram_dout*/),
  .wren_a(we),
  .enable_a(ram_cs),
  .enable_b(1'b1),
/*  .wren_a(~sam_we_n),
  .enable_a(sam_we_n),
  .enable_b(sam_we_n),
*/
  //.clock_b(clk),
  //.address_b(vmem),
  //.q_b(ram_dout_b)
  .clock_b(clk),
  .address_b(hard_reset ? 16'h71: sam_a),
  .data_b( 8'h00),
  .wren_b( hard_reset ? 1'b1:1'b0),
  .q_b(vdg_data)
);

// BOOT ROMS  - inspired from COCO3

localparam     [1:0]    BOOT0 = 2'd0;
localparam     [1:0]    BOOT1 = 2'd1;
localparam     [1:0]    BOOT2 = 2'd2;
localparam     [1:0]    BOOT3 = 2'd3;

localparam     [5:0]    BOOT  = 6'd0;

// 16KROM : CoCo ROMS 0x8000-0xBFFF ext & bas
wire  COCO2_ROM_WR = (ioctl_index[7:0] == {BOOT0, BOOT})  & ioctl_wr;
// 16KROM : Dragon32 ROMS 0x8000-0xBFFF ext & bas
wire  DGN32_ROM_WR = (ioctl_index[7:0] == {BOOT1, BOOT}) & ioctl_wr;
// 32KROM : Dragon64 16K 0x8000-0xBFFF then Dragon64_ext 16K 0x8000-0BFFF
wire  DGN64_ROM_WR = (ioctl_index[7:0] == {BOOT2, BOOT}) & ioctl_wr;
// 32KROM : Disk Drivers 8K CoCo2, then 8K D32, then 8K D64, then 8K unused
wire  DISKS_ROM_WR = (ioctl_index[7:0] == {BOOT3, BOOT}) & ioctl_wr;

always @(posedge clk) begin
	if (roms_reset) roms_loaded <= 4'b0000 ;
	if (COCO2_ROM_WR) roms_loaded[0] <= 1'b1 ;
	if (DGN32_ROM_WR) roms_loaded[1] <= 1'b1 ;
	if (DGN64_ROM_WR) roms_loaded[2] <= 1'b1 ;
	if (DISKS_ROM_WR) roms_loaded[3] <= 1'b1 ;
end

dpram_1r1w #(16384, 14) roms_coco2
(
		.wrclock(clk),
		.wren(COCO2_ROM_WR),
		.wraddress(ioctl_addr[13:0]),
		.data(ioctl_data[7:0]),
		
		.rdclock(clk),
		.rdaddress(cpu_addr[13:0]),
		.q(rom8_dout_tandy)
);
	
dpram_1r1w #(16384, 14) roms_D32
(
		.wrclock(clk),
		.wren(DGN32_ROM_WR),
		.wraddress(ioctl_addr[13:0]),
		.data(ioctl_data[7:0]),
		
		.rdclock(clk),
		.rdaddress(cpu_addr[13:0]),
		.q(rom8_dout_dragon)
);

dpram_1r1w #(32768, 15)  roms_D64
(
		.wrclock(clk),
		.wren(DGN64_ROM_WR),
		.wraddress(ioctl_addr[14:0]),
		.data(ioctl_data[7:0]),
		
		.rdclock(clk),
		.rdaddress({DDRB[2] & ~pia1_portb_out[2], cpu_addr[13:0]}),
		.q(rom8_64_1)
);

dpram_1r1w #(24576, 15)  roms_disk   // 4th slot is unused so it's only 24K
(
		.wrclock(clk),
		.wren(DISKS_ROM_WR),
		.wraddress(ioctl_addr[14:0]),
		.data(ioctl_data[7:0]),
		
		.rdclock(clk),
		.rdaddress({dragon64, ~dragon64 & dragon, cpu_addr[12:0]}),
		.q(romC_disk_dout)
);
	
	
// 8k extended basic rom
// Do we need an option to enable/disable extended basic rom?
assign rom8_dout = dragon ?   rom8_dout_dragon : rom8_dout_tandy;
wire [7:0] rom8_dout_dragon;
wire [7:0] rom8_dout_tandy;

reg [7:0] rom8_64_1_2;
wire [7:0] rom8_64_1;


// there must be another solution
reg cart_loaded;
wire disk_cart_enabled_d ; // to detect disk_cart_enabled changes
wire ioctl_download_d ; // to detect ioctl_download changes

always @(posedge clk) begin
  disk_cart_enabled_d <= disk_cart_enabled ;
  ioctl_download_d <= ioctl_download ;  
   if (~ioctl_download & ioctl_download_d & load_cart) 
    cart_loaded <= ioctl_addr > 15'h100;  // there is an image there if not 0
   else if (disk_cart_enabled)
    cart_loaded <= 1'b0; //SRH 1/26/25 no FIRQ on disk
end
  
wire load_cart = ioctl_index[5:0] == 1;

dpram #(.addr_width_g(14), .data_width_g(8)) romC(
  .clock_a(clk),
  .address_a(cpu_addr[13:0]),
  .q_a(romC_cart_dout),
  .enable_a(romC_cs & cart_loaded),  // if no cart, no enable, so we can dismount it for real

  .clock_b(clk),
  .address_b(ioctl_addr[13:0]),
  .data_b(ioctl_data),
  .wren_b(ioctl_wr & load_cart)
);


//assign romC_dout = disk_cart_enabled ? (dragon ? romC_dragondisk_dout :romC_disk_dout ) : romC_cart_dout;
assign romC_dout = disk_cart_enabled ? romC_disk_dout : romC_cart_dout;

wire [2:0] s_device_select;

wire da0;
wire [7:0] ma_ram_addr;
wire ras_n, cas_n,sam_we_n;
reg [15:0] sam_a;
reg ras_n_r;
reg cas_n_r;
reg q_r;

always @(posedge clk)
begin
	if (~reset_n)
	begin
		ras_n_r<=0;
		cas_n_r<=0;
		q_r<=0;
	end
	else if  (clk_enable == 1)  
	begin
	     if (ras_n == 1 && ras_n_r == 0  && clk_E == 1 )
		  begin
		    //  ram_datao <= sram_i.d(ram_datao'range);
			ram_dout<=vdg_data;
			romC_dout2<=romC_dout;
			rom8_dout2<=rom8_dout;
			pia_dout2<=pia_dout;
			pia1_dout2<=pia1_dout;
			rom8_64_1_2<=rom8_64_1;

        end
        if (ras_n == 0 && ras_n_r == 1)
          sam_a[7:0]<= ma_ram_addr;
        else if (cas_n == 0 && cas_n_r == 1)
          sam_a[15:8] <= ma_ram_addr;

		  if (clk_Q == 1 && q_r == 0)
		  begin
		   ram_dout_b<=vdg_data;// <= sram_i.d(ram_datao'range);
        end
        q_r <= clk_Q;


        ras_n_r <= ras_n;
        cas_n_r <= cas_n;
	end
end
			//assign ram_dout=vdg_data;

			// SAM is now generating the clocks E & Q 
			// the signal clk_enable used to pace the clock at the correct speed has to be extracted from SAM
			
wire	WR_CK_ENA;
wire 	VClk;



mc6883 sam(
			.clk(clk),
			// .clk_ena(WR_CK_ENA),		// not used anymore, SAM is pacing the clock by itself
			.spd_ena(clk_enable),
			.turbo(turbo),          // user request speed change, SAM has to do the choices
			.reset(~trig_reset_n),

			//-- input
			.addr(cpu_addr),
			.rw_n(cpu_rw),

			//-- vdg signals
			.da0(da0),
			.hs_n(hs_n),
			.vclk(VClk), // not sure why this clock doesn't work to put it into the video chip

			//-- peripheral address selects
			.s_device_select(s_device_select),

			//-- clock generation
			.clk_e(clk_E),
			.clk_q(clk_Q),

			//-- dynamic addresses
			.z_ram_addr(ma_ram_addr),

			//-- ram
			.ras0_n(ras_n),
			.cas_n(cas_n),
			.we_n(sam_we_n),

			.WR_CK_ENA(WR_CK_ENA),
			
			.dbg()//sam_dbg
);

/*
reg [7:0] cs74138_reg;
reg [2:0] s_device_select_reg;

always @(posedge clk)
begin
	s_device_select_reg<=s_device_select;
	cs74138_reg<=cs74138;
end
*/

wire nc;
wire [7:0] cs74138;
assign {
  nc,io_cs, pia1_cs, pia_orig_cs,
  romC_cs, romA_cs, rom8k_cs,
  ram_cs
} = cs74138;

assign rom8_cs = romA_cs | rom8k_cs ; // to not disturb the 74138 stuff : it's nice to see images of physical original components in here
												  // nevertheless, the external ROM doesn't need this rom8/romA separation.

ttl_74ls138_p u11(
.a(s_device_select[0]),
.b(s_device_select[1]),
.c(s_device_select[2]),
.g1(1),//comes from CART_SLENB#
.g2a(1),//come from E NOR cs_sel(2)
//.g2b(clk_E),
.g2b(1),
//.g2a( ~(cpu_rw | S[2])),
//.g2b(~(E| S[2])),//come from E NOR cs_sel(2)
.y(cs74138)
);



wire fs_n;
wire hs_n;

pia6520 pia(
  .data_out(pia_dout),
  .data_in(cpu_dout),
  .addr(cpu_addr[1:0]),
  .strobe(pia_cs),
  .we(we),
  .irq(irq),
  .porta_in(kb_rows),
  .porta_out(),
  .portb_in(),
  .portb_out(kb_cols),
  .ca1_in(hs_n),
  .ca2_in(),
  .cb1_in(fs_n),  
  .cb2_in(),
  .ca2_out(sela), // used for joy & snd
  .cb2_out(selb), // used for joy & snd
  .clk(clk),
  .clk_ena(clk_enable),
  .reset(~reset_n)
);


wire casdin0;
wire rsout1;
wire [5:0] dac_data;
wire sela,selb;
wire snden;
// 1 bit sound
assign sndout = pia1_portb_out[1];
wire [7:0] DDRB;
pia6520 pia1(
  .data_out(pia1_dout),
  .data_in(cpu_dout),
  .addr(cpu_addr[1:0]),
  .strobe(pia1_cs),
  .we(we),
  .irq(firq),
  .porta_in({6'd0,casdout}),
  .porta_out({dac_data,casdin0,rsout1}),
  .portb_in(dragon64?8'b00000001:8'b00000000), // from dragon64 schematic 
  .portb_out(pia1_portb_out),
  .DDRB(DDRB),
  .ca1_in(dragon64?1'b1:1'b0), // from dragon64 schematic - this should be held high
  .ca2_in(),
//  .cb1_in(cart_loaded & reset_n & clk_Q), // cartridge inserted
  .cb1_in(disk_cart_enabled & dragon ? cart_firq : cart_loaded & reset_n & clk_Q), // cartridge inserted 
  .cb2_in(),
  .ca2_out(cas_relay),
  .cb2_out(snden),
  .clk(clk),
  .clk_ena(clk_enable),
  .reset(~reset_n)
);

// These are the two debug lines.
wire [7:0] dbg1_b1 ;
wire [7:0] dbg1_b2 ;
wire [7:0] dbg2_b1 ;
wire [7:0] dbg2_b2 ;
wire [7:0] dbg3_b1 ;

always @(posedge clk)
begin
   if (~reset_n) begin
	   dbg1_b1<=8'd0 ;
	   dbg1_b2<=8'd0 ;
	   dbg2_b1<=8'd0 ;
	   dbg2_b2<=8'd0 ;
	 //  dbg3_b1<=8'd0 ;
	end
   if (cpu_addr==16'hffff && cpu_rw && clk_E) begin dbg1_b1 <= cpu_din ; end
   if (cpu_addr==16'hfffe && cpu_rw && clk_E) begin dbg2_b1 <= cpu_din ; end
	if (cpu_rw && clk_E && dbg1_b1 != 8'd0 && dbg2_b1=='0) begin dbg1_b2 <= cpu_addr[15:8]; dbg2_b2 <= cpu_addr[7:0]; dbg2_b1<=8'b1 ; end
   // if (cpu_addr==16'hb4b3 && cpu_rw && clk_E) begin dbg3_b1 <= cpu_din ; end
	dbg3_b1 <= { 7'd0, reset_n } ;
end 

assign DLine1 = {
5'b11111,						// '#'  (to mark the data)
4'b0000, cas_relay,
5'b10000,						// space

5'b10101,						// '>'  (to mark the data)
4'b0000, turbo,
5'b10000,						// space

5'b11010,						// ':'  (to mark the data)
3'b0,ram_dout_b[7:6],
5'b10000,						// space

{23{5'b10000}}
};

// two is a copy of 1 for now, but we will use this for debugging
// the disk controller
assign DLine2 = {

//5'b10000,						// space
5'b11111,						// '#'  (to mark the data)
1'b0,pia1_portb_out[7:4],
5'b10000,						// space

5'b10101,						// '>'  (to mark the data)
1'b0,pia1_portb_out[3:0],
5'b10000,						// space

5'b11010,						// ':'  (to mark the data)
3'b0,ram_dout_b[7:6],
5'b10000,						// space

1'b0,dbg1_b2[3:0],
1'b0,dbg1_b2[7:4],
1'b0,dbg2_b2[3:0],
1'b0,dbg2_b2[7:4],
5'b10000,						// space
1'b0,dbg1_b1[3:0],
1'b0,dbg1_b1[7:4],
1'b0,dbg2_b1[3:0],
1'b0,dbg2_b1[7:4],
5'b10000,						// space
1'b0,dbg3_b1[3:0],
1'b0,dbg3_b1[7:4],
5'b10000,						// space
1'b0,roms_loaded,

{9{5'b10000}}
};

mc6847pace vdg(
  .clk(clk),
//  .clk_ena(clk_enable),//VClk - vclk doesn't seem to work
  .clk_ena(VClk),//VClk - vclk doesn't seem to work
  .reset(~trig_reset_n),
  .da0(da0),
  .dd(ram_dout_b),
  .hs_n(hs_n),
  .fs_n(fs_n),
  .an_g(pia1_portb_out[7]), // PIA1 port B
  .an_s(ram_dout_b[7]),
  .intn_ext(pia1_portb_out[4]),
  .gm(pia1_portb_out[6:4]), // [2:0] pin 6 (gm2),5 (gm1) & 4 (gm0) PIA1 port B
  .css(pia1_portb_out[3]),
  .inv(ram_dout_b[6]),
  .red(red),
  .green(green),
  .blue(blue),
  .hsync(hsync),
  .vsync(vsync),
  .hblank(hblank),
  .vblank(vblank),
  .artifact_enable(artifact_enable),
  .artifact_set(1'b0),
  .artifact_phase(artifact_phase),
  .overscan(overscan),

  .o_v_count(v_count),
  .o_h_count(h_count),


  .pixel_clock(vclk),
  .cvbs()
);



// hilo comes from the dac as the comparator 
// of whether the joystick value is higher or lower than the amount being probed
// we need to pass it through the keyboard matrix so it flows into here
wire hilo;
keyboard kb(
.clk_sys(clk),
.reset(~reset_n),
.dragon(dragon),
.ps2_key(ps2_key),
.addr(kb_cols),
.kb_rows(kb_rows),
.kblayout(kblayout),
.Fn(),
.modif(),
.joystick_1_button(joy1[4]),
.joystick_2_button(joy2[4]),
.joystick_hilo(hilo)

);


// the DAC isn't really a DAC but represents the DAC chip on the schematic. 
// All the signals have been digitized before it gets here.

reg [15:0] dac_joya1;
reg [15:0] dac_joya2;

//	Limits for joysticks - set to total limits 0,255 SRH 6/5/24
always @(negedge clk) begin

	if (joy_use_dpad)
	  begin
		dac_joya1[15:8] <= 8'd128;
		dac_joya1[7:0]  <= 8'd128;
		
		dac_joya2[15:8] <= 8'd128;
		dac_joya2[7:0]  <= 8'd128;
		
		if (joy1[0])	// right
			dac_joya1[15:8] <= 8'd255;

		if (joy1[1])	// left
			dac_joya1[15:8] <= 8'd0;
		
		if (joy1[2])	// down
			dac_joya1[7:0] <= 8'd255;

		if (joy1[3])	// up
			dac_joya1[7:0] <= 8'd0;
		
		if (joy2[0])	// right
			dac_joya2[15:8] <= 8'd255;

		if (joy2[1])	// left
			dac_joya2[15:8] <= 8'd0;
		
		if (joy2[2])	// down
			dac_joya2[7:0] <= 8'd255;

		if (joy2[3])	// upimg_mounted
			dac_joya2[7:0] <= 8'd0;
	  end
	else
	  begin
		dac_joya1 <= joya1;
		dac_joya2 <= joya2;
	  end
end

dac dac(
.clk(clk),
.joya1(dac_joya1),
.joya2(dac_joya2),
.dac(dac_data),
.cass_snd(cass_snd),
.snden(snden),
.snd(),
.hilo(hilo),
.selb(selb),
.sela(sela),
.sound(sound)

);

//dragon 64 has a serial module wired in based on addr[2] - this module is a stub that returns values to make things work 
wire [7:0] acia_dout;
acia acia (
   .clk(clk),
   .addr(cpu_addr[2:0]),
   .data(acia_dout)
  );


//
//  Floppy Controller Support
//
//  This isn't tested / modified for dragon yet

wire    ff40_write;
wire    FF40_read;
wire    wd1793_data_read;
wire    wd1793_read;
wire    wd1793_write;
wire	dragon_addr3, dragon_addr2; 		
wire	fdc_halt;

assign	halt = dragon ? 1'b0 : fdc_halt;

assign 	dragon_addr2 = dragon_addr3 && ~(dragon && cpu_addr[2]) ; 
assign 	dragon_addr3 = dragon ^ cpu_addr[3] ;
assign   ff40_write = (WR_CK_ENA && io_cs && ({cpu_rw, dragon_addr3, cpu_addr[2:0]} == 5'b00000));

assign   FF40_read =            ({io_cs, dragon_addr3, cpu_addr[2:0]} == 5'h10);
assign   wd1793_data_read =    (io_cs && dragon_addr2);

assign   wd1793_read =        (cpu_rw && io_cs && dragon_addr2 && (clk_E || clk_Q));
assign   wd1793_write =        (~cpu_rw && io_cs && dragon_addr2 && WR_CK_ENA);

fdc coco_fdc(
    .CLK(clk),                     // clock
	 .dragon(dragon),
    .RESET_N(reset_n),                       // async reset
    .ADDRESS(cpu_addr[1:0]),               // i/o port addr for wd1793 & FF48+
    .DATA_IN(cpu_dout),                    // data in
    .DATA_HDD(io_out),                  // data out
    .HALT(fdc_halt),                       // DMA request [dragon is no halt]
    .NMI_09(nmi),
    .FIRQ(cart_firq),

//    FDC host r/w handling
    .FF40_CLK(ff40_write),
    .FF40_ENA(1'b1),                    // Disabled in coco2

    .FF40_RD(FF40_read),
    .WD1793_RD(wd1793_data_read),

    .WD1793_WR_CTRL(wd1793_write),
    .WD1793_RD_CTRL(wd1793_read),


    //     SD block level interface
    .img_mounted(img_mounted[3:0]),         // signaling that new image has been mounted
    .img_readonly(img_readonly),         // mounted as read only. valid only for active bit in img_mounted
    .img_size(img_size),                // size of image in bytes. 1MB MAX!

    .sd_lba(sd_lba[0:3]),
    .sd_blk_cnt(sd_blk_cnt[0:3]),             // number of blocks-1, total size ((sd_blk_cnt+1)*(1<<(BLKSZ+7))) must be <= 16384!
    .sd_rd(sd_rd[3:0]),
    .sd_wr(sd_wr[3:0]),
    .sd_ack(sd_ack[3:0]),

    //     SD byte level access. Signals for 2-PORT altsyncram.
    .sd_buff_addr(sd_buff_addr),
    .sd_buff_dout(sd_buff_dout),
    .sd_buff_din(sd_buff_din[0:3]),
    .sd_buff_wr(sd_buff_wr)

);



// Start of Cassette Save
// Generate 1.78 Mhz [enable] GP clk
reg clk_1_78;
reg [4:0] clk_178_ctr;

always @ (negedge clk or negedge reset_n)
begin
	if(!reset_n)
	begin
		clk_1_78 <= 1'b0;
		clk_178_ctr <= 5'b00000;
	end
	else
	begin
		clk_1_78 <= 1'b0;
		clk_178_ctr <= clk_178_ctr + 1'b1;
		if (clk_178_ctr == 5'd27)
		begin
			clk_1_78 <= 1'b1;
		end
	end
end

Cassette_Write CoCo3_Cassette_Write(
		.RESET_N(reset_n),
		.CLK(clk),
		.CLK_1_78(clk_1_78),

		.CASS_REWIND_RECORD(CASS_REWIND_RECORD),
		.MOTOR_ON(cas_relay),
		.DTOA_CODE(dac_data),
		
// 		SD block level interface
		.img_mounted(img_mounted[4]), 	// signaling that new image has been mounted
		.img_readonly(img_readonly),	// mounted as read only. valid only for active bit in img_mounted
		.img_size(img_size),    		// size of image in bytes. 

		.sd_lba(sd_lba[4]),
		.sd_blk_cnt(sd_blk_cnt[4]), 	// number of blocks-1, total size ((sd_blk_cnt+1)*(1<<(BLKSZ+7))) must be <= 16384!
		.sd_rd(sd_rd[4]),
		.sd_wr(sd_wr[4]),
		.sd_ack(sd_ack[4]),

// 		SD byte level access. Signals for 2-PORT altsyncram.
		.sd_buff_addr(sd_buff_addr),
		.sd_buff_dout(sd_buff_dout),
		.sd_buff_din(sd_buff_din[4]),
		.sd_buff_wr(sd_buff_wr)
);


endmodule
