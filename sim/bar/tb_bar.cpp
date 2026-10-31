// Verilator testbench for tape_bar.sv: generates sync timing (15 kHz or VGA),
// a test picture, and dumps one frame as PPM (active area only).
#include "Vtape_bar.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <vector>
int main(int argc, char **argv) {
	int vga = atoi(argv[1]); int prog = atoi(argv[2]); const char *out = argv[3];
	Vtape_bar *t = new Vtape_bar;
	int clocks = vga ? 684 : 1368, lines = vga ? 525 : 262, hsw = vga ? 82 : 100, act_x0 = vga ? 130 : 250, act_w = vga ? 512 : 1024, act_y0 = vga ? 40 : 20, act_h = vga ? 424 : 212;
	t->enable = 1; t->playing = 1; t->progress = prog;
	std::vector<unsigned char> img(act_w * act_h * 3);
	for (int frame = 0; frame < 3; frame++)
		for (int y = 0; y < lines; y++)
			for (int x = 0; x < clocks; x++) {
				t->hs_n = !(x < hsw); t->vs_n = !(y < 2);
				bool act = x >= act_x0 && x < act_x0 + act_w && y >= act_y0 && y < act_y0 + act_h;
				t->r_in = act ? 20 : 0; t->g_in = act ? 20 : 0; t->b_in = act ? 50 : 0;   // blue MSX screen
				t->clk = 0; t->eval(); t->clk = 1; t->eval();
				if (frame == 2 && act) {
					int px = x - act_x0 + 1, py = y - act_y0;   // output is one clock late
					if (px < act_w) { unsigned char *p = &img[(py * act_w + px) * 3]; p[0] = t->r_out << 2; p[1] = t->g_out << 2; p[2] = t->b_out << 2; }
				}
			}
	FILE *f = fopen(out, "wb"); fprintf(f, "P6 %d %d 255\n", act_w, act_h); fwrite(img.data(), 1, img.size(), f); fclose(f);
	delete t; return 0;
}
