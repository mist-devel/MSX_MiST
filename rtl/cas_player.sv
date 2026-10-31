//============================================================================
//  cas_player.sv - .CAS tape player for the MSX2 MiST core
//
//  The .CAS image is mounted through the MiST OSD as SD image 1 and read
//  sector by sector (two sector buffer, the next sector is prefetched).
//  The data is converted to the MSX cassette signal (FSK) and fed to the
//  cassette input of the PSG, so the original BIOS routines load it:
//      BLOAD"CAS:",R   RUN"CAS:"   CLOAD
//  Like a real data recorder, the tape only moves while the MSX turns the
//  cassette motor on.
//
//  CAS format: every block starts with the marker 1F A6 DE BA CC 13 7D 74
//  (normally on a multiple of 8 bytes, but not in every .CAS file around,
//  so the marker is searched at any position).  A block starting with D0h/D3h/EAh (file header
//  of a binary/BASIC/ASCII file) gets a long header, the others a short one.
//
//  Signal: 1200 baud (or 2400 baud), bit "0" = one cycle at 1200 Hz,
//  bit "1" = two cycles at 2400 Hz, byte = start bit 0, 8 data bits (LSB
//  first), two stop bits 1.
//
//  Copyright (c) 2026 - GNU General Public License v2 or later.
//============================================================================

module cas_player
#(
	parameter [12:0] DIV_1200 = 13'd4474,  // 21.477 MHz / 4800 (quarter of a 1200 baud bit)
	parameter [12:0] DIV_2400 = 13'd2237
)
(
	input             clk,          // 21.477 MHz
	input             rewind,       // OSD: rewind the tape (level or pulse)
	input             fast,         // 1: 2400 baud
	input             motor,        // 1: cassette motor on

	// MiST SD image 1
	input             img_mounted,
	input      [31:0] img_size,
	output reg [31:0] sd_lba,
	output reg        sd_rd,
	input             sd_ack,
	input       [8:0] sd_buff_addr,
	input       [7:0] sd_buff_dout,
	input             sd_buff_wr,

	output            cas_out,      // to the cassette input of the PSG
	output            active,       // a tape is inserted and not at its end
	output reg  [7:0] progress      // tape position, 0..255 = 0..100%
);

localparam [15:0] HDR_LONG   = 16'd8000;   // "1" bits of a long header  (6.7 s at 1200 baud)
localparam [15:0] HDR_SHORT  = 16'd2000;   // "1" bits of a short header (1.7 s at 1200 baud)
localparam [15:0] SIL_LONG   = 16'd4800;   // silence before a file (ticks, 1 s at 1200 baud)
localparam [15:0] SIL_SHORT  = 16'd1200;   // silence before a data block (0.25 s)

//////////////////////////////////////////////////////////////////////////////
// image state

reg  [31:0] size    = 0;
reg         loaded  = 0;
reg  [31:0] pos     = 0;            // position of the next byte in the image
reg         new_img = 0;

//////////////////////////////////////////////////////////////////////////////
// two sector buffer: half = sector number bit 0

reg   [7:0] buff[0:1023];
reg   [9:0] rd_addr;
reg   [7:0] rd_data;
reg         ld_half;                // half that is being loaded

always @(posedge clk) begin
	if(sd_ack & sd_buff_wr) buff[{ld_half, sd_buff_addr}] <= sd_buff_dout;
	rd_data <= buff[rd_addr];
end

reg  [22:0] tag[0:1];                 // sector number held by each half
reg   [1:0] tag_ok = 0;

wire [22:0] cur_sec  = pos[31:9];
wire [22:0] next_sec = cur_sec + 1'd1;
wire        cur_ok   = tag_ok[cur_sec[0]]  && (tag[cur_sec[0]]  == cur_sec);
wire        next_ok  = tag_ok[next_sec[0]] && (tag[next_sec[0]] == next_sec);
wire        next_in  = ({next_sec, 9'd0} < size);

// sector loader
reg   [1:0] ld_state = 0;
reg  [22:0] ld_sec;
reg         ld_discard = 0;         // image changed while a sector was being read
always @(posedge clk) begin
	case(ld_state)
		0: if(loaded && !new_img) begin
				ld_discard <= 0;
				if(!cur_ok) begin
					ld_sec  <= cur_sec;
					ld_half <= cur_sec[0];
					tag_ok[cur_sec[0]] <= 0;
					sd_lba  <= {9'd0, cur_sec};
					sd_rd   <= 1;
					ld_state <= 1;
				end else if(next_in && !next_ok) begin
					ld_sec  <= next_sec;
					ld_half <= next_sec[0];
					tag_ok[next_sec[0]] <= 0;
					sd_lba  <= {9'd0, next_sec};
					sd_rd   <= 1;
					ld_state <= 1;
				end
			end
		1: if(sd_ack) begin             // transfer started
				sd_rd <= 0;
				ld_state <= 2;
			end
		2: if(!sd_ack) begin            // transfer done
				tag[ld_half]    <= ld_sec;
				tag_ok[ld_half] <= ~ld_discard;
				ld_state <= 0;
			end
		default: ld_state <= 0;
	endcase

	if(new_img) begin
		tag_ok <= 0;
		if(ld_state != 0) ld_discard <= 1;
	end
end

//////////////////////////////////////////////////////////////////////////////
// signal generator: a "tick" is a quarter of a bit

reg  [12:0] div_cnt = 0;
reg         tick;
always @(posedge clk) begin
	tick <= 0;
	if(motor) begin
		if(div_cnt == 0) begin
			div_cnt <= fast ? DIV_2400 - 1'd1 : DIV_1200 - 1'd1;
			tick <= 1;
		end else div_cnt <= div_cnt - 1'd1;
	end
end

//////////////////////////////////////////////////////////////////////////////
// player

localparam ST_IDLE    = 4'd0;
localparam ST_CHECK   = 4'd1;
localparam ST_MARK    = 4'd2;
localparam ST_PEEK    = 4'd3;
localparam ST_SILENCE = 4'd4;
localparam ST_HEADER  = 4'd5;
localparam ST_LOAD    = 4'd6;
localparam ST_SEND    = 4'd7;
localparam ST_EOF     = 4'd8;
localparam ST_WAIT    = 4'd9;

reg   [3:0] state = ST_IDLE;
reg   [3:0] rstate;                 // state to return to after ST_WAIT
reg   [1:0] wait_cnt;
reg   [3:0] mk_idx;
reg  [15:0] count;                  // silence ticks / header bits
reg  [10:0] shifter;                // bits of the current byte, LSB first
reg   [3:0] bits;                   // bits left in the shifter
reg   [1:0] quarter;                // quarter of the current bit
reg         bitval;
reg         level;
reg         sending;                // a bit (or silence) is being produced
reg         silence;

wire [63:0] marker = 64'h1FA6DEBACC137D74;
wire  [7:0] mk_byte = marker[63 - {mk_idx[2:0], 3'b000} -: 8];

always @(posedge clk) begin
	reg old_rewind;

	new_img <= 0;
	if(img_mounted) begin
		size    <= img_size;
		loaded  <= (img_size != 0);
		new_img <= 1;
	end

	old_rewind <= rewind;

	// bit / silence waveform, one quarter of a bit per tick
	if(tick && sending) begin
		if(silence) begin
			level <= 0;
		end else begin
			case(quarter)
				0: level <= 1;
				1: level <= ~bitval;    // "1": H L H L, "0": H H L L
				2: level <= bitval;
				3: level <= 0;
			endcase
		end
		quarter <= quarter + 1'd1;
		if(quarter == 3) sending <= 0;
	end

	case(state)
		ST_IDLE:
			if(loaded && motor && !new_img) state <= ST_CHECK;

		ST_CHECK:   // start of a byte: end of tape? block marker?
			// the marker is searched at every byte (many .CAS files have
			// blocks that do not start on a multiple of 8 bytes); a marker
			// can cross the end of a sector, so near the end of the sector
			// wait for the next one too.
			if(pos >= size) state <= ST_EOF;
			else if(cur_ok && (next_ok || !next_in || pos[8:0] <= 9'd504)) begin
				mk_idx  <= 0;
				rd_addr <= pos[9:0];
				state   <= ST_WAIT;
				rstate  <= ((pos + 32'd8) <= size) ? ST_MARK : ST_LOAD;
			end

		ST_WAIT:    // BRAM read latency
			begin
				wait_cnt <= wait_cnt + 1'd1;
				if(wait_cnt == 1) begin
					wait_cnt <= 0;
					state <= rstate;
				end
			end

		ST_MARK:    // compare up to 8 bytes with the block marker
			if(rd_data != mk_byte) begin
				rd_addr <= pos[9:0];          // not a marker: send the byte
				rstate  <= ST_LOAD;
				state   <= ST_WAIT;
			end else if(mk_idx == 7) begin
				pos   <= pos + 32'd8;         // marker found: new block
				state <= ST_PEEK;
			end else begin
				mk_idx  <= mk_idx + 1'd1;
				rd_addr <= pos[9:0] + {7'd0, mk_idx[2:0]} + 10'd1;
				rstate  <= ST_MARK;
				state   <= ST_WAIT;
			end

		ST_PEEK:    // first byte of the block: header length
			if(pos >= size) state <= ST_EOF;
			else if(cur_ok) begin
				rd_addr <= pos[9:0];
				rstate  <= ST_SILENCE;
				state   <= ST_WAIT;
				count   <= 16'hFFFF;    // marks "peek pending"
			end

		ST_SILENCE:
			begin
				if(count == 16'hFFFF) begin
					// rd_data = first byte of the block
					if(rd_data == 8'hD0 || rd_data == 8'hD3 || rd_data == 8'hEA) begin
						count   <= SIL_LONG;
						shifter <= 11'd1;           // long header follows
					end else begin
						count   <= SIL_SHORT;
						shifter <= 11'd0;           // short header follows
					end
				end else if(!sending) begin
					if(count == 0) begin
						count <= shifter[0] ? HDR_LONG : HDR_SHORT;
						state <= ST_HEADER;
					end else begin
						count   <= count - 1'd1;
						silence <= 1;
						quarter <= 3;               // one tick of silence
						sending <= 1;
					end
				end
			end

		ST_HEADER:
			if(!sending) begin
				if(count == 0) begin
					state <= ST_CHECK;              // the block data follows
				end else begin
					count   <= count - 1'd1;
					silence <= 0;
					bitval  <= 1;
					quarter <= 0;
					sending <= 1;
				end
			end

		ST_LOAD:    // rd_data = byte at pos
			begin
				shifter <= {2'b11, rd_data, 1'b0};
				bits    <= 4'd11;
				state   <= ST_SEND;
			end

		ST_SEND:
			if(!sending) begin
				if(bits == 0) begin
					pos   <= pos + 1'd1;
					state <= ST_CHECK;
				end else begin
					bitval  <= shifter[0];
					shifter <= {1'b1, shifter[10:1]};
					bits    <= bits - 1'd1;
					silence <= 0;
					quarter <= 0;
					sending <= 1;
				end
			end

		ST_EOF:
			begin
				level <= 0;
			end

		default: state <= ST_IDLE;
	endcase

	if((rewind & ~old_rewind) | new_img) begin
		pos     <= 0;
		state   <= ST_IDLE;
		sending <= 0;
		level   <= 0;
		wait_cnt <= 0;
	end
end

//////////////////////////////////////////////////////////////////////////////
// progress = pos * 256 / size (serial division, 8 quotient bits)

reg  [3:0] pg_step = 0;
reg [32:0] rem;
reg  [7:0] q;

always @(posedge clk) begin
	if(pg_step == 0) begin
		rem  <= {1'b0, pos};
		q    <= 0;
		pg_step <= 1;
	end else if(pg_step <= 8) begin
		if({rem[31:0], 1'b0} >= {1'b0, size}) begin
			rem <= {rem[31:0], 1'b0} - {1'b0, size};
			q   <= {q[6:0], 1'b1};
		end else begin
			rem <= {rem[31:0], 1'b0};
			q   <= {q[6:0], 1'b0};
		end
		pg_step <= pg_step + 1'd1;
	end else begin
		progress <= (!loaded || size == 0) ? 8'd0 : (pos >= size) ? 8'd255 : q;
		pg_step <= 0;
	end
end

assign cas_out = level;
assign active  = loaded & (state != ST_EOF);

endmodule
