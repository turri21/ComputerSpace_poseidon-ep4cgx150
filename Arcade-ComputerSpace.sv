//============================================================================
//  Arcade: Computer Space
//
//  Port to MiSTer
//  Copyright (C) 2017-2019 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module guest_top
(
	input         CLOCK_27,
`ifdef USE_CLOCK_50
	input         CLOCK_50,
`endif

	output        LED,
	output [VGA_BITS-1:0] VGA_R,
	output [VGA_BITS-1:0] VGA_G,
	output [VGA_BITS-1:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,

`ifdef USE_HDMI
	output        HDMI_RST,
	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_PCLK,
	output        HDMI_DE,
	inout         HDMI_SDA,
	inout         HDMI_SCL,
	input         HDMI_INT,
`endif

	input         SPI_SCK,
	inout         SPI_DO,
	input         SPI_DI,
	input         SPI_SS2,    // data_io
	input         SPI_SS3,    // OSD
	input         CONF_DATA0, // SPI_SS for user_io

`ifdef USE_QSPI
	input         QSCK,
	input         QCSn,
	inout   [3:0] QDAT,
`endif
`ifndef NO_DIRECT_UPLOAD
	input         SPI_SS4,
`endif

	output [12:0] SDRAM_A,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nWE,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nCS,
	output  [1:0] SDRAM_BA,
	output        SDRAM_CLK,
	output        SDRAM_CKE,

`ifdef DUAL_SDRAM
	output [12:0] SDRAM2_A,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_DQML,
	output        SDRAM2_DQMH,
	output        SDRAM2_nWE,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nCS,
	output  [1:0] SDRAM2_BA,
	output        SDRAM2_CLK,
	output        SDRAM2_CKE,
`endif

	output        AUDIO_L,
	output        AUDIO_R,
`ifdef I2S_AUDIO
	output        I2S_BCK,
	output        I2S_LRCK,
	output        I2S_DATA,
`endif
`ifdef I2S_AUDIO_HDMI
	output        HDMI_MCLK,
	output        HDMI_BCK,
	output        HDMI_LRCK,
	output        HDMI_SDATA,
`endif
`ifdef SPDIF_AUDIO
	output        SPDIF,
`endif
`ifdef USE_AUDIO_IN
	input         AUDIO_IN,
`endif
`ifdef USE_MIDI_PINS
	output        MIDI_OUT,
	input         MIDI_IN,
`endif
`ifdef SIDI128_EXPANSION
	input         UART_CTS,
	output        UART_RTS,
	inout         EXP7,
	inout         MOTOR_CTRL,
`endif
	input         UART_RX,
	output        UART_TX
);

`ifdef NO_DIRECT_UPLOAD
localparam bit DIRECT_UPLOAD = 0;
wire SPI_SS4 = 1;
`else
localparam bit DIRECT_UPLOAD = 1;
`endif

`ifdef USE_QSPI
localparam bit QSPI = 1;
assign QDAT = 4'hZ;
`else
localparam bit QSPI = 0;
`endif

`ifdef VGA_8BIT
localparam VGA_BITS = 8;
`else
localparam VGA_BITS = 6;
`endif

`ifdef USE_HDMI
localparam bit HDMI = 1;
assign HDMI_RST = 1'b1;
`else
localparam bit HDMI = 0;
`endif

`ifdef BIG_OSD
localparam bit BIG_OSD = 1;
`define SEP "-;",
`else
localparam bit BIG_OSD = 0;
`define SEP
`endif

assign LED   = 0;

`include "build_id.v" 
localparam CONF_STR = {
	"A.COMSPC;;",
	"-;",
	"O2,Color,No,Yes;",
	"O45,Scanlines,Off,25%,50%,75%;",
	"O6,Two Games per coin,No,Yes;",
   "O7,Replay,No,Yes;",
	"-;",
  "DIP;",
	"-;",
	"T0,Reset;",
//	"J1,Thrust,Fire,Start,Coin;",
//	"jn,B,A,Start,R;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys = CLOCK_50;
wire clk_5m, clk_vid;
wire pll_locked;

pll pll
(
	.inclk0(CLOCK_50),
	.areset(0),
	.c0(clk_vid),
	.c1(clk_5m),
	.locked(pll_locked)
);

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;

wire scanlines = status[5:4];
wire sw_2playpercoin = status[6];
wire sw_replay = status[7];
      
wire scandoubler_disable;
wire no_csync;
wire ypbpr;

wire [15:0] joystick_0, joystick_1;
wire [15:0] joy = joystick_0 | joystick_1;

wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire [15:0] ioctl_index;

wire [10:0] ps2_key = {key_strobe, key_pressed, key_extended, key_code};

wire        key_pressed;
wire [7:0]  key_code;
wire        key_strobe;
wire        key_extended;

user_io #(.STRLEN($size(CONF_STR)>>3), .SD_IMAGES(1), .PS2DIV(500), .FEATURES(32'h0 | (BIG_OSD << 13) | (HDMI << 14))) user_io
(	
	.clk_sys          (clk_sys          ),
	.clk_sd           (clk_sys          ),
	.conf_str         (CONF_STR         ),
	.SPI_CLK          (SPI_SCK          ),
	.SPI_SS_IO        (CONF_DATA0       ),
	.SPI_MISO         (SPI_DO           ),
	.SPI_MOSI         (SPI_DI           ),
	.buttons          (buttons          ),
	.switches         (switches         ),
	.no_csync         (no_csync         ),
	.ypbpr            (ypbpr            ),

	.ps2_kbd_clk      (ps2_kbd_clk      ),
	.ps2_kbd_data     (ps2_kbd_data     ),
	.key_strobe       (key_strobe       ),
	.key_pressed      (key_pressed      ),
	.key_extended     (key_extended     ),
	.key_code         (key_code         ),
	.joystick_0       (joystick_0       ),
	.joystick_1       (joystick_1       ),

	.status           (status           ),
	.scandoubler_disable(scandoubler_disable),

`ifdef USE_HDMI
	.i2c_start        (i2c_start        ),
	.i2c_read         (i2c_read         ),
	.i2c_addr         (i2c_addr         ),
	.i2c_subaddr      (i2c_subaddr      ),
	.i2c_dout         (i2c_dout         ),
	.i2c_din          (i2c_din          ),
	.i2c_ack          (i2c_ack          ),
	.i2c_end          (i2c_end          ),
`endif
	
//// SD CARD
   .sd_lba           (sd_lba           ),
	.sd_rd            (sd_rd            ),
	.sd_wr            (sd_wr            ),
	.sd_ack           (sd_ack           ),
	.sd_ack_conf      (sd_ack_conf      ),
	.sd_conf          (sd_conf          ),
	.sd_sdhc          (1'b1             ),
	.sd_dout          (sd_buff_dout     ),
	.sd_din           (sd_buff_din      ),
	.sd_buff_addr     (sd_buff_addr     ),
	.sd_dout_strobe   (sd_buff_wr       ),
   .img_mounted      (img_mounted      ),
	.img_size         (img_size         )
);

data_io data_io(
	.clk_sys       ( clk_sys         ),
	.SPI_SCK       ( SPI_SCK         ),
	.SPI_SS2       ( SPI_SS2         ),
	.SPI_DI        ( SPI_DI          ),
	.ioctl_download( ioctl_download  ),
	.ioctl_index   ( ioctl_index     ),
	.ioctl_wr      ( ioctl_wr        ),
	.ioctl_addr    ( ioctl_addr      ),
	.ioctl_dout    ( ioctl_dout      )
);

wire m_left   = joy[1];
wire m_right  = joy[0];
wire m_thrust = joy[4];
wire m_fire   = joy[5];
wire m_start  = joy[6];
wire m_coin   = joy[7];

// Load DIP-SW
reg [7:0] dipsw[8];
always @(posedge clk_sys) begin
  if (ioctl_wr && (ioctl_index==254) && !ioctl_addr[24:3])
    dipsw[ioctl_addr[2:0]] <= ioctl_dout;
end

wire HBlank, VBlank;
wire VSync, HSync;

reg ce_pix;
always @(posedge clk_vid) begin
	reg [1:0] div;

	div <= div + 1'd1;
	ce_pix <= !div;
end


mist_video #(.COLOR_DEPTH(4), .SD_HCNT_WIDTH(11), .USE_BLANKS(1), .OUT_COLOR_DEPTH(VGA_BITS), .BIG_OSD(BIG_OSD)) mist_video(
	.clk_sys          (clk_vid          ),
	.SPI_SCK          (SPI_SCK          ),
	.SPI_SS3          (SPI_SS3          ),
	.SPI_DI           (SPI_DI           ),
	.R                (r                ),
	.G                (g                ),
	.B                (b                ),
	.HSync            (HSync            ),
	.VSync            (VSync            ),
	.HBlank           (HBlank           ),
	.VBlank           (VBlank           ),
	.VGA_R            (VGA_R            ),
	.VGA_G            (VGA_G            ),
	.VGA_B            (VGA_B            ),
	.VGA_VS           (VGA_VS           ),
	.VGA_HS           (VGA_HS           ),
	.ce_divider       (3'd1             ),
	.no_csync         (no_csync         ),
	.scandoubler_disable(scandoubler_disable),
	.ypbpr            (ypbpr            ),
	.scanlines        (scanlines        ),
	.rotate           (2'b00            ),
	.blend            (1'b0             )
);



wire [15:0] audio;
assign AUDIO_L = audio;
assign AUDIO_R = AUDIO_L;

`ifdef I2S_AUDIO
i2s i2s (
	.reset(1'b0),
	.clk(clk_sys),
	.clk_rate(32'd50_000_000),

	.sclk(I2S_BCK),
	.lrclk(I2S_LRCK),
	.sdata(I2S_DATA),

	.left_chan(audio),
	.right_chan(audio)
);

`endif

wire reset = status[0] | buttons[1] | ~pll_locked;

computer_space_top computerspace
(
	.reset( reset ),

	.clock_50(clk_sys),
	.game_clk(clk_5m),

	.signal_ccw(m_left),
	.signal_cw(m_right),
	.signal_thrust(m_thrust),
	.signal_fire(m_fire),
	.signal_start(m_start),
	.signal_coin(m_coin),

	.sw_2playpercoin(sw_2playpercoin),
	.sw_replay(sw_replay),

	.hsync(HSync),
	.vsync(VSync),
	.hblank(HBlank),
	.vblank(VBlank),
	.video(video),

	.audio(audio)
);

wire [3:0] video;

wire [5:0] rs,gs,bs, ro,go,bo, rc,gc,bc, rm,gm,bm;
wire [3:0] r,g,b;

assign {rs,gs,bs} = ~video[0] ? 18'd0 : status[2] ? {6'b0111,6'b0111,6'b0111} : {6'b0111,6'b0111,6'b0111};
assign {rc,gc,bc} = ~video[1] ? 18'd0 : status[2] ? {6'b0000,6'b1111,6'b1111} : {6'b0111,6'b0111,6'b0111};
assign {ro,go,bo} = ~video[2] ? 18'd0 : status[2] ? {6'b1111,6'b1111,6'b0000} : {6'b1111,6'b1111,6'b1111};

assign rm = rs + ro + rc;
assign gm = gs + go + gc;
assign bm = bs + bo + bc;

assign r = (rm[5:4] ? 4'b1111 : rm[3:0]) ^ {4{inv}};
assign g = (gm[5:4] ? 4'b1111 : gm[3:0]) ^ {4{inv}};
assign b = (bm[5:4] ? 4'b1111 : bm[3:0]) ^ {4{inv}};

reg inv;
always @(posedge clk_5m) begin
	reg old_vs, cur_inv;
	old_vs <= VSync;

	cur_inv <= cur_inv | video[3];
	if (~old_vs & VSync) {inv,cur_inv} <= {cur_inv, 1'b0};
end

endmodule
