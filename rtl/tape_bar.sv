//============================================================================
//  tape_bar.sv - cassette progress bar drawn over the MSX picture
//
//  The bar is placed relative to the measured line length and number of
//  lines per frame, so it works at 15 kHz and 31 kHz, 50 and 60 Hz.
//  It stays on screen while the cassette motor is on (and one second after).
//
//  Copyright (c) 2026 - GNU General Public License v2 or later.
//============================================================================

module tape_bar
(
	input            clk,          // 21.48 MHz (pixel clock domain of the VDP)
	input            enable,       // OSD option
	input            playing,      // tape inserted and motor on
	input      [7:0] progress,     // 0..255

	input            hs_n,
	input            vs_n,
	input      [5:0] r_in,
	input      [5:0] g_in,
	input      [5:0] b_in,
	output reg [5:0] r_out,
	output reg [5:0] g_out,
	output reg [5:0] b_out
);

// keep the bar one second after the motor stops (between two blocks)
reg [24:0] hold = 0;
always @(posedge clk) begin
	if(playing) hold <= 25'd21_480_000;
	else if(hold) hold <= hold - 1'd1;
end
wire show = enable & (playing | (hold != 0));

// line / frame measurement
reg        hs_d, vs_d;
reg [11:0] hcnt = 0, line_len = 12'd1368;
reg [10:0] vcnt = 0, frame_lines = 11'd262;
always @(posedge clk) begin
	hs_d <= hs_n;
	vs_d <= vs_n;
	if(~&hcnt) hcnt <= hcnt + 1'd1;
	if(hs_d & ~hs_n) begin
		line_len <= hcnt;
		hcnt     <= 0;
		if(~&vcnt) vcnt <= vcnt + 1'd1;
	end
	if(vs_d & ~vs_n) begin
		frame_lines <= vcnt;
		vcnt        <= 0;
	end
end

// geometry: x from 5/16 to 13/16 of the line, y at 3/4 of the frame
reg [11:0] x0, x1, xfill;
reg [10:0] y0, y1;
always @(posedge clk) begin
	reg [11:0] xlen;
	reg [19:0] f;
	reg  [7:0] t;
	xlen  = {1'b0, line_len[11:1]};
	x0    <= {2'b00, line_len[11:2]} + {4'b0000, line_len[11:4]};
	x1    <= {2'b00, line_len[11:2]} + {4'b0000, line_len[11:4]} + xlen;
	f     = xlen * progress;
	xfill <= {2'b00, line_len[11:2]} + {4'b0000, line_len[11:4]} + f[19:8];
	t     = frame_lines[10:5] + 8'd2;                                  // thickness ~ 1/32 of the frame
	y0    <= frame_lines - {2'b00, frame_lines[10:2]};
	y1    <= frame_lines - {2'b00, frame_lines[10:2]} + t;
end

wire in_y   = (vcnt >= y0) && (vcnt < y1);
wire in_x   = (hcnt >= x0) && (hcnt < x1);
wire border = (vcnt == y0) || (vcnt == y1 - 1'd1) || (hcnt < x0 + 12'd3) || (hcnt >= x1 - 12'd3);
wire filled = (hcnt < xfill);

always @(posedge clk) begin
	if(show && in_x && in_y) begin
		if(border)      {r_out, g_out, b_out} <= {6'd63, 6'd63, 6'd63};   // white frame
		else if(filled) {r_out, g_out, b_out} <= {6'd8,  6'd56, 6'd16};   // green: tape already read
		else            {r_out, g_out, b_out} <= {6'd6,  6'd6,  6'd12};   // dark: rest of the tape
	end else begin
		{r_out, g_out, b_out} <= {r_in, g_in, b_in};
	end
end

endmodule
