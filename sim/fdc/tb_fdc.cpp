// Verilator testbench for msx_fdc.sv (Philips registers + WD2793 + MiST SD image)
#include "Vmsx_fdc.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <cstring>

static Vmsx_fdc *t;
static uint64_t cyc = 0;
static std::vector<uint8_t> img;
static int errors = 0;
static int strobe_len = 8;        // CPU strobe length in clk21m cycles (8 ~ 3.58MHz, 3 ~ turbo)

// ---- MiST user_io SD model (drive 0) ----
enum { SD_IDLE, SD_WAIT, SD_RD, SD_WR, SD_END } sd_st = SD_IDLE;
int sd_cnt = 0, sd_i = 0, sd_lat = 0;
uint32_t sd_lba_l = 0;
int sd_reads = 0, sd_writes = 0;

static void sd_model() {
	switch (sd_st) {
	case SD_IDLE:
		t->sd_buff_wr = 0;
		if (t->sd_rd || t->sd_wr) { sd_st = SD_WAIT; sd_cnt = 300 + (rand() % 3000); sd_lba_l = t->sd_lba; }
		break;
	case SD_WAIT:
		if (--sd_cnt == 0) {
			t->sd_ack = 1; sd_i = 0;
			if (t->sd_wr) { sd_st = SD_WR; t->sd_buff_addr = 0; sd_cnt = 3; }
			else          { sd_st = SD_RD; sd_cnt = 2; }
		}
		break;
	case SD_RD:   // one byte every 8 cycles
		if (t->sd_buff_wr) { t->sd_buff_wr = 0; t->sd_buff_addr = (t->sd_buff_addr + 1) & 511; sd_cnt = 7; break; }
		if (--sd_cnt == 0) {
			if (sd_i == 512) { sd_st = SD_END; sd_cnt = 5; sd_reads++; break; }
			uint32_t off = sd_lba_l * 512 + sd_i;
			t->sd_buff_addr = sd_i; t->sd_buff_dout = off < img.size() ? img[off] : 0; t->sd_buff_wr = 1; sd_i++;
		}
		break;
	case SD_WR:
		if (--sd_cnt == 0) {
			uint32_t off = sd_lba_l * 512 + sd_i;
			if (off < img.size()) img[off] = t->sd_buff_din;
			sd_i++;
			if (sd_i == 512) { sd_st = SD_END; sd_cnt = 5; sd_writes++; break; }
			t->sd_buff_addr = sd_i; sd_cnt = 3;
		}
		break;
	case SD_END:
		if (--sd_cnt == 0) { t->sd_ack = 0; sd_st = SD_IDLE; }
		break;
	}
}

static void tick() {
	t->clk = 0; t->eval();
	t->clk = 1; t->eval();
	sd_model();
	t->eval();
	cyc++;
}
static void idle(int n) { while (n--) tick(); }

static void wr(int a, int v) {
	t->adr = a; t->din = v; t->cs = 1; t->wr = 1;
	idle(strobe_len);
	t->wr = 0; idle(1); t->cs = 0; idle(4 + strobe_len);
}
static int rd(int a) {
	t->adr = a; t->cs = 1; t->rd = 1;
	idle(strobe_len - 1);
	t->eval();
	int v = t->dout;
	idle(1);
	t->rd = 0; idle(1); t->cs = 0; idle(4 + strobe_len);
	return v;
}
static void mount(uint32_t size) {
	t->img_size = size; t->img_mounted = 1; idle(1); t->img_mounted = 0; idle(10);
}
static bool wait_ready(const char *what, int maxc = 4000000) {
	uint64_t start = cyc;
	while (cyc - start < (uint64_t)maxc) { if (!(rd(7) & 0x40)) return true; }   // INTRQ (like the disk ROM)
	printf("FAIL: %s: still busy\n", what); errors++; return false;
}
static void check(const char *what, int got, int exp) {
	if (got != exp) { printf("FAIL: %s: got %02X expected %02X\n", what, got, exp); errors++; }
	else printf("ok  : %s = %02X\n", what, got);
}

static int read_sector(int track, int side, int sector, std::vector<uint8_t> &out) {
	wr(3, track); wr(0, 0x18);                  // seek (no verify), head load
	wait_ready("seek"); rd(0);
	wr(4, side); wr(2, sector);
	wr(0, 0x80);                                // read sector
	out.clear();
	uint64_t start = cyc;
	while (cyc - start < 20000000) {
		int s = rd(7);
		if (!(s & 0x80)) out.push_back(rd(3));  // DRQ
		else if (!(s & 0x40)) break;           // INTRQ
	}
	return rd(0);                               // status (clears INTRQ)
}
static int write_sector(int track, int side, int sector, const std::vector<uint8_t> &in) {
	wr(3, track); wr(0, 0x18);
	wait_ready("seek"); rd(0);
	wr(4, side); wr(2, sector);
	wr(0, 0xA0);                                // write sector
	size_t i = 0;
	uint64_t start = cyc;
	while (cyc - start < 20000000) {
		int s = rd(7);
		if (!(s & 0x80)) { wr(3, i < in.size() ? in[i] : 0); i++; }
		else if (!(s & 0x40)) break;
	}
	if (i != 512) { printf("FAIL: write sector: %zu bytes accepted\n", i); errors++; }
	return rd(0);
}

static void make_image(uint32_t size) {
	img.resize(size);
	for (uint32_t i = 0; i < size; i++) img[i] = (uint8_t)((i >> 9) * 7 + (i & 511) * 3 + (i >> 17));
}

static void sector_test(int track, int side, int sector, bool double_sided) {
	std::vector<uint8_t> d;
	int st = read_sector(track, side, sector, d);
	uint32_t lsn = double_sided ? ((track * 2 + side) * 9 + sector - 1) : (track * 9 + sector - 1);
	bool same = d.size() == 512 && !memcmp(d.data(), &img[lsn * 512], 512);
	char msg[100];
	snprintf(msg, sizeof msg, "read T%02d S%d sector %d: %zu bytes %s, status", track, side, sector, d.size(), same ? "match" : "DIFFER");
	check(msg, st & 0xFD, 0x00);      // ignore index bit
	if (!same) errors++;
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	t = new Vmsx_fdc;
	t->reset = 1; idle(20); t->reset = 0; idle(20);

	for (int pass = 0; pass < 2; pass++) {
		strobe_len = pass ? 3 : 8;
		printf("=== pass %d: CPU strobe %d cycles (%s)\n", pass, strobe_len, pass ? "turbo" : "3.58MHz");
		make_image(737280);
		mount(737280);
		check("7FFC side reg after reset", rd(4), 0x00);
		wr(5, 0x80);                                // motor on, drive A
		check("7FFD drive reg", rd(5), 0x80);
		wr(0, 0x00);                                // restore
		wait_ready("restore");
		check("track register after restore", rd(1), 0);
		int s7 = rd(7);
		check("7FFF after restore (/INTRQ=0, /DRQ=1)", s7 & 0xC0, 0x80);
		check("status after restore (not ready=0, track0=1)", rd(0) & 0x84, 0x04);
		check("7FFF after status read (/INTRQ=1)", rd(7) & 0xC0, 0xC0);

		sector_test(0, 0, 1, true);
		sector_test(5, 1, 3, true);
		sector_test(79, 1, 9, true);
		sector_test(40, 0, 7, true);

		// write
		std::vector<uint8_t> w(512);
		for (int i = 0; i < 512; i++) w[i] = (uint8_t)(i ^ 0x5A ^ pass);
		int st = write_sector(12, 1, 4, w);
		check("write sector status", st & 0xFD, 0x00);
		idle(20000);
		uint32_t lsn = (12 * 2 + 1) * 9 + 3;
		bool same = !memcmp(w.data(), &img[lsn * 512], 512);
		printf("%s: written sector reached the image\n", same ? "ok  " : "FAIL"); if (!same) errors++;
		sector_test(12, 1, 4, true);

		// no disk in drive B
		wr(5, 0x81);
		check("status with drive B selected (not ready)", rd(0) & 0x80, 0x80);
		wr(5, 0x80);

		// single sided image
		make_image(368640);
		mount(368640);
		sector_test(3, 0, 2, false);
		sector_test(79, 0, 9, false);
		printf("sd reads %d, writes %d\n", sd_reads, sd_writes);
	}
	printf("\n%s (%d errors)\n", errors ? "FDC TEST FAILED" : "FDC TEST PASSED", errors);
	delete t;
	return errors ? 1 : 0;
}
