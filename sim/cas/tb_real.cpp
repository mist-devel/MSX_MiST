// Verilator testbench: plays a real .CAS file through cas_player.sv (built with
// a short bit time) and decodes the FSK signal into blocks: header length,
// bytes.  The result is compared with the blocks found in the file by
// searching the marker at any position (like openMSX does).
//   usage: tb_real file.cas
#include "Vcas_player.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

static Vcas_player *t;
static uint64_t cyc = 0;
static std::vector<uint8_t> img;
static const double TICK = 40.0;            // DIV_2400 used for the build

enum { SD_IDLE, SD_WAIT, SD_RD, SD_END } sd_st = SD_IDLE;
static int sd_cnt, sd_i; static uint32_t sd_lba_l;
static void sd_model() {
	switch (sd_st) {
	case SD_IDLE: t->sd_buff_wr = 0; if (t->sd_rd) { sd_st = SD_WAIT; sd_cnt = 2000 + rand() % 20000; sd_lba_l = t->sd_lba; } break;
	case SD_WAIT: if (--sd_cnt == 0) { t->sd_ack = 1; sd_i = 0; sd_st = SD_RD; sd_cnt = 2; } break;
	case SD_RD:
		if (t->sd_buff_wr) { t->sd_buff_wr = 0; sd_cnt = 3; break; }
		if (--sd_cnt == 0) {
			if (sd_i == 512) { sd_st = SD_END; sd_cnt = 5; break; }
			uint32_t off = sd_lba_l * 512 + sd_i;
			t->sd_buff_addr = sd_i; t->sd_buff_dout = off < img.size() ? img[off] : 0; t->sd_buff_wr = 1; sd_i++;
		}
		break;
	case SD_END: if (--sd_cnt == 0) { t->sd_ack = 0; sd_st = SD_IDLE; } break;
	}
}

struct Run { int lvl; double ticks; };
static std::vector<Run> runs;
static int last_lvl = 0; static uint64_t last_edge = 0;
static void tick() {
	t->clk = 0; t->eval(); t->clk = 1; t->eval(); sd_model(); t->eval();
	int l = t->cas_out;
	if (l != last_lvl) { runs.push_back({last_lvl, (cyc - last_edge) / TICK}); last_edge = cyc; last_lvl = l; }
	cyc++;
}

struct Block { bool lng; std::vector<uint8_t> data; };

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	if (argc < 2) { fprintf(stderr, "usage: tb_real file.cas\n"); return 2; }
	FILE *f = fopen(argv[1], "rb"); if (!f) { perror(argv[1]); return 2; }
	int c; while ((c = fgetc(f)) != EOF) img.push_back(c); fclose(f);

	// expected blocks
	const uint8_t mk[8] = {0x1F,0xA6,0xDE,0xBA,0xCC,0x13,0x7D,0x74};
	std::vector<Block> exp;
	for (size_t p = 0; p < img.size(); ) {
		if (p + 8 <= img.size() && !memcmp(&img[p], mk, 8)) {
			p += 8; Block b; b.lng = p < img.size() && (img[p] == 0xD0 || img[p] == 0xD3 || img[p] == 0xEA);
			exp.push_back(b); continue;
		}
		if (exp.empty()) exp.push_back(Block{false, {}});      // data before the first marker
		exp.back().data.push_back(img[p++]);
	}

	t = new Vcas_player;
	t->fast = 1; t->motor = 1;
	t->img_size = img.size(); t->img_mounted = 1; tick(); t->img_mounted = 0;
	uint64_t limit = (uint64_t)(img.size() * 11 * 4 * TICK * 1.2) + (uint64_t)(exp.size() * 14000 * 4 * TICK) + 50000000ULL;
	while (t->active && cyc < limit) tick();
	runs.push_back({last_lvl, (cyc - last_edge) / TICK});
	runs.push_back({1, 1}); runs.push_back({0, 10});
	printf("%s: %zu bytes, %zu blocks, played in %llu clocks, active=%d progress=%d\n",
		argv[1], img.size(), exp.size(), (unsigned long long)cyc, t->active, t->progress);

	// runs -> bits, silence (>3.5 ticks low) splits blocks
	std::vector<Block> got;
	std::vector<int> bits; bool in_silence = true;
	auto flush = [&]() {
		if (bits.empty()) return;
		size_t i = 0; int ones = 0;
		while (i < bits.size() && bits[i] == 1) { ones++; i++; }
		Block b; b.lng = ones > 5000;
		for (; i + 11 <= bits.size(); i += 11) {
			uint8_t v = 0; for (int k = 0; k < 8; k++) v |= bits[i + 1 + k] << k;
			if (bits[i] != 0 || bits[i + 9] != 1 || bits[i + 10] != 1) { printf("  framing error in block %zu byte %zu\n", got.size(), b.data.size()); break; }
			b.data.push_back(v);
		}
		printf("  decoded block %zu: %s header (%d ones), %zu bytes\n", got.size(), b.lng ? "long " : "short", ones, b.data.size());
		got.push_back(b); bits.clear();
	};
	for (size_t i = 0; i + 1 < runs.size(); ) {
		Run h = runs[i];
		if (h.lvl == 0) {
			if (h.ticks > 3.5) { flush(); }
			i++; continue;
		}
		Run l = runs[i + 1];
		if (h.ticks > 1.5 && h.ticks < 2.5 && l.ticks > 1.5 && l.ticks < 2.5) { bits.push_back(0); i += 2; }
		else if (h.ticks > 1.5 && h.ticks < 2.5 && l.ticks >= 2.5) { bits.push_back(0); i += 1; runs[i].ticks -= 2; }
		else if (h.ticks > 0.5 && h.ticks < 1.5 && i + 3 < runs.size()) {
			bits.push_back(1);
			if (runs[i + 3].ticks >= 1.5) { runs[i + 3].ticks -= 1; i += 3; } else i += 4;   // "1" then silence
		}
		else i++;
	}
	flush();
	(void)in_silence;

	int err = 0;
	if (got.size() != exp.size()) { printf("FAIL: %zu blocks decoded, %zu expected\n", got.size(), exp.size()); err++; }
	for (size_t i = 0; i < got.size() && i < exp.size(); i++) {
		if (got[i].lng != exp[i].lng) { printf("FAIL: block %zu header length\n", i); err++; }
		if (got[i].data != exp[i].data) { printf("FAIL: block %zu data (%zu vs %zu bytes)\n", i, got[i].data.size(), exp[i].data.size()); err++; }
	}
	if (t->active || t->progress != 255) { printf("FAIL: tape not at its end\n"); err++; }
	printf("%s\n", err ? "REAL CAS TEST FAILED" : "REAL CAS TEST PASSED");
	delete t;
	return err ? 1 : 0;
}
