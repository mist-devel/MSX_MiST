Simulazioni (non servono per compilare il core)

Strumenti: NVC (VHDL) e Verilator (SystemVerilog).

VHDL, dalla cartella sim:
  ./analyze.sh                               analizza tutti i sorgenti VHDL in sim/build/work
  cd build
  nvc --std=1993 --work=work -a --relaxed ../sdram_model.vhd ../tb_sys.vhd ../tb_loader.vhd ../tb_cart.vhd
  nvc --std=1993 --work=work -e -j tb_loader -r           test del caricatore (mapper, ROM di sistema, OCM-BIOS)
  nvc --std=1993 --work=work -e -j tb_cart -r             test dei mapper delle cartucce
  nvc --std=1993 --work=work -e -j -gPRELOAD=true -gMAP1=2 -gMAP2=5 \
      -gSYS_HEX=../systest/sys.hex -gCART1_HEX=../systest/cart1.hex -gCART2_HEX=../systest/cart2.hex tb_sys -r
                                             test di sistema veloce (SDRAM precaricata)
  aggiungere -gVERIFY=true -gFAST_INIT=false -gINIT_WAIT_US=400 (senza PRELOAD) per il test completo con
  il caricamento byte per byte e i tempi reali di inizializzazione della SDRAM (lento, circa 20 minuti)
  core MSX1: -gMSX1_G=1 -gSYS_HEX=../systest/sys_msx1.hex -gSYS_PRE_HEX=../systest/sys_msx1_pre.hex
             (sys_msx1.hex contiene systest assemblato con -DMSX1T; -gCART2_HEX=none lascia vuoto lo slot 2,
             dove allora compare l'interfaccia disco)

Il programma di prova systest/systest.asm (sjasmplus) gira come MAIN-ROM e scrive i risultati in C000h.

SystemVerilog, con Verilator:
  cas:  verilator --cc --exe --build -O2 -Wno-fatal ../../rtl/cas_player.sv tb_cas.cpp --top-module cas_player -o tb_cas
  cas con un file .CAS vero (bit accorciati, controlla blocchi, intestazioni lunghe/corte e tutti i byte):
        verilator --cc --exe --build -O2 -Wno-fatal -GDIV_1200=13\'d80 -GDIV_2400=13\'d40 --Mdir obj_real -o tb_real \
                  ../../rtl/cas_player.sv tb_real.cpp
        ./obj_real/tb_real gioco.cas
  fdc:  verilator --cc --exe --build -O2 -Wno-fatal -Wno-WIDTH ../../rtl/msx_fdc.sv ../../rtl/wd1793.sv tb_fdc.cpp --top-module msx_fdc -o tb_fdc
