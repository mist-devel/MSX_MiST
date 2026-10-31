// Verilator testbench for cas_player.sv: plays a synthetic .CAS image and
// decodes the FSK signal back into bytes, the way the MSX BIOS does.
#include "Vcas_player.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <string>

static Vcas_player *t;
static uint64_t cyc = 0;
static std::vector<uint8_t> img;
static int errors = 0;

// SD model (drive 1, read only)
enum { SD_IDLE, SD_WAIT, SD_RD, SD_END } sd_st = SD_IDLE;
int sd_cnt, sd_i; uint32_t sd_lba_l; int sd_reads = 0;
static void sd_model() {
	switch (sd_st) {
	case SD_IDLE: t->sd_buff_wr = 0; if (t->sd_rd) { sd_st = SD_WAIT; sd_cnt = 2000 + rand() % 20000; sd_lba_l = t->sd_lba; } break;
	case SD_WAIT: if (--sd_cnt == 0) { t->sd_ack = 1; sd_i = 0; sd_st = SD_RD; sd_cnt = 2; } break;
	case SD_RD:
		if (t->sd_buff_wr) { t->sd_buff_wr = 0; sd_cnt = 7; break; }
		if (--sd_cnt == 0) {
			if (sd_i == 512) { sd_st = SD_END; sd_cnt = 5; sd_reads++; break; }
			uint32_t off = sd_lba_l * 512 + sd_i;
			t->sd_buff_addr = sd_i; t->sd_buff_dout = off < img.size() ? img[off] : 0x00; t->sd_buff_wr = 1; sd_i++;
		}
		break;
	case SD_END: if (--sd_cnt == 0) { t->sd_ack = 0; sd_st = SD_IDLE; } break;
	}
}

// FSK decoder
static double tick_len = 4474.0;
static int last_lvl = 0; static uint64_t last_edge = 0;
struct Run { int lvl; double ticks; };
static std::vector<Run> runs;
static void decode_sample() {
	int l = t->cas_out;
	if (l != last_lvl) { runs.push_back({last_lvl, (cyc - last_edge) / tick_len}); last_edge = cyc; last_lvl = l; }
}

static void tick() {
	t->clk = 0; t->eval(); t->clk = 1; t->eval(); sd_model(); t->eval(); decode_sample(); cyc++;
}
static void idle(uint64_t n) { while (n--) tick(); }

// bits from runs: high run of 2 ticks + low 2 = "0", high 1 + low 1 + high 1 + low 1 = "1"
struct Bit { int v; uint64_t idx; };
static std::vector<int> runs_to_bits(std::vector<int> *gaps) {
	std::vector<int> bits;
	for (size_t i = 0; i + 1 < runs.size(); ) {
		Run h = runs[i];
		if (h.lvl == 0) { if (h.ticks > 3.5 && gaps) gaps->push_back((int)bits.size()); i++; continue; }  // silence / gap
		Run l = runs[i + 1];
		if (h.ticks > 1.5 && h.ticks < 2.5 && l.ticks > 1.5 && l.ticks < 2.5) { bits.push_back(0); i += 2; }
		else if (h.ticks > 1.5 && h.ticks < 2.5 && l.ticks >= 2.5) { bits.push_back(0); i += 1; runs[i].ticks -= 2; } // 0 then silence
		else if (h.ticks > 0.5 && h.ticks < 1.5 && i + 3 < runs.size()) { bits.push_back(1); i += 4; }
		else { i++; }
	}
	return bits;
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	t = new Vcas_player;
	const uint8_t mk[8] = {0x1F,0xA6,0xDE,0xBA,0xCC,0x13,0x7D,0x74};
	// CAS: [marker][10 x D0 + "TEST  "][marker][start,end,exec + 600 bytes payload]
	std::vector<uint8_t> payload1, payload2;
	for (int i = 0; i < 10; i++) payload1.push_back(0xD0);
	for (char c : std::string("TEST  ")) payload1.push_back(c);
	payload2 = {0x00,0x90, 0x5F,0x92, 0x00,0x90};
	for (int i = 0; i < 600; i++) payload2.push_back((uint8_t)(i * 13 + 7));
	auto add = [&](const std::vector<uint8_t> &p) { while (img.size() % 8) img.push_back(0); img.insert(img.end(), mk, mk + 8); img.insert(img.end(), p.begin(), p.end()); };
	add(payload1); add(payload2);
	std::vector<uint8_t> expect = payload1; expect.insert(expect.end(), payload2.begin(), payload2.end());
	printf("CAS image: %zu bytes\n", img.size());

	for (int pass = 0; pass < 2; pass++) {
		bool fast = pass == 1;
		tick_len = fast ? 2237.0 : 4474.0;
		t->fast = fast;
		runs.clear(); last_edge = cyc; last_lvl = t->cas_out;
		t->motor = 0;
		t->img_size = img.size(); t->img_mounted = 1; idle(1); t->img_mounted = 0;
		idle(100000);
		if (t->cas_out) { printf("FAIL: output active with motor off\n"); errors++; }
		t->motor = 1;
		// play the header block, then stop the motor for a while (like the BIOS after "Found:")
		uint64_t hdr_time = (uint64_t)((4800 + 8000 * 4 + 16 * 44 + 1200) * tick_len);
		idle(hdr_time);
		printf("progress after the header block: %d/255 (block %zu of %zu bytes)\n", t->progress, (size_t)16 + 8, img.size());
		t->motor = 0; idle(3000000); t->motor = 1;
		idle((uint64_t)((2000 * 4 + 612 * 44 + 2000) * tick_len));
		printf("pass %d (%s): active=%d sd_reads=%d runs=%zu\n", pass, fast ? "2400 baud" : "1200 baud", t->active, sd_reads, runs.size());
		if (t->active) { printf("FAIL: tape should be at its end\n"); errors++; }
		if (t->progress != 255) { printf("FAIL: progress at the end = %d\n", t->progress); errors++; } else printf("ok  : progress at the end = 255\n");

		// decode (close the last run, then add a long low run like the end of the tape)
		runs.push_back({last_lvl, (cyc - last_edge) / tick_len}); last_edge = cyc;
		runs.push_back({1, 1.0}); runs.push_back({0, 10.0});
		std::vector<int> gaps;
		std::vector<int> bits = runs_to_bits(&gaps);
		// skip headers: find frames (0 + 8 data + 11)
		std::vector<uint8_t> got;
		int ones = 0; size_t hdrs = 0;
		for (size_t i = 0; i < bits.size(); ) {
			if (bits[i] == 1) { ones++; i++; continue; }
			if (ones > 500) hdrs++;
			ones = 0;
			if (i + 11 > bits.size()) break;
			uint8_t v = 0;
			for (int b = 0; b < 8; b++) v |= bits[i + 1 + b] << b;
			if (bits[i + 9] != 1 || bits[i + 10] != 1) { printf("FAIL: stop bits at byte %zu\n", got.size()); errors++; }
			got.push_back(v);
			i += 11;
		}
		printf("decoded %zu bytes, %zu headers, %zu silences\n", got.size(), hdrs, gaps.size());
		bool same = got == expect;
		if (!same) {
			errors++;
			printf("FAIL: data differs (expected %zu bytes)\n", expect.size());
			for (size_t i = 0; i < got.size() && i < expect.size(); i++) if (got[i] != expect[i]) { printf("  first diff at %zu: %02X vs %02X\n", i, got[i], expect[i]); break; }
		} else printf("ok  : all bytes match\n");
		if (hdrs != 2) { printf("FAIL: expected 2 headers\n"); errors++; }
		// rewind for the next pass
		t->rewind = 1; idle(2); t->rewind = 0; idle(10);
	}
	printf("\n%s (%d errors)\n", errors ? "CAS TEST FAILED" : "CAS TEST PASSED", errors);
	delete t;
	return errors ? 1 : 0;
}
