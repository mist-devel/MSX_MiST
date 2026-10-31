# MSX2 per MiST

Core MSX2 per la scheda MiST, ricavato dal core MSX di MiST (OneChipMSX / OCM-PLD di KdL, port di gyurco).
È organizzato come un MSX2 vero (tipo Philips NMS 8245) e **non usa più SD virtuale, VHD o hard disk**:
ROM, cartucce, dischetti e cassette si caricano dal menu OSD.

## Cosa fa

| Funzione | Dettagli |
|---|---|
| Slot | 0 = MAIN-ROM (+ MSX-MUSIC in 0-2 se presente), 1 e 2 = cartucce, 3-1 = SUB-ROM, 3-2 = RAM mapper (come sui Philips), 3-3 = DISK-ROM + controller WD2793. Dal menu la RAM si può spostare in 3-0 (come sui Sony) |
| Cartucce (.ROM) | Slot 1 e 2, fino a 8 MB ciascuna. Il mapper viene riconosciuto in automatico: ROM semplice (8–64 KB, indirizzo di partenza preso dall'header), Konami, Konami SCC (con il suono SCC), ASCII 8K, ASCII 16K, Generic 8K. Si può anche forzare dal menu |
| Dischetti (.DSK) | Drive A:, immagini da 720 KB (2DD) e 360 KB (1DD), in lettura e scrittura (le modifiche finiscono nel file .DSK sulla SD) |
| Cassette (.CAS) | Si caricano con i comandi del BIOS: `BLOAD"CAS:",R`, `RUN"CAS:"`, `CLOAD`. Il nastro avanza solo quando l'MSX accende il motore, come su un registratore vero. Vanno bene anche i .CAS con i blocchi non allineati a 8 byte. Velocità 1200 o 2400 baud, riavvolgimento dal menu, suono della cassetta attivabile, barra di avanzamento sullo schermo durante il caricamento (disattivabile) |
| Video | VDP V9938 (oppure ID V9958), 50/60 Hz automatico o forzato, uscita 15 kHz (RGB/SCART) o 31 kHz (VGA) |
| Audio | PSG, SCC (cartucce Konami), MSX-MUSIC (FM, facoltativo), con volumi regolabili |
| CPU | Z80 a 3,58 MHz come l'originale, con modalità turbo 5,37 / 6,96 / 8,06 / 10,74 MHz |
| RAM | Memory mapper da 64 KB a 4 MB (predefinito 512 KB) |
| Tastiera | Layout italiano (predefinito), US o giapponese |
| Altro | Due joystick (scambiabili), mouse MSX sulla porta A, orologio RP-5C01 sincronizzato con l'RTC della MiST |

## Il menu

Sulla MiST il menu OSD si apre con **F12**: il tasto lo gestisce il firmware della scheda, non il core.
Per aprirlo con **F11** solo in questo core, aggiungi in fondo al file `mist.ini` nella radice della SD:

```
[MSX2]
key_remap=44,45
```

`44` è il codice USB di F11 e `45` quello di F12: con questa riga F11 si comporta come F12 (anche F12 continua a funzionare).

Voci del menu:

- **Cartridge slot 1 / slot 2**: carica un file `.ROM` nello slot. L'MSX si riavvia da solo, come quando inserisci una cartuccia e riaccendi.
- **Disk drive A:**: inserisce un `.DSK`. Puoi cambiare disco senza riavviare. Premendo Backspace sulla voce il disco viene estratto.
- **Cassette**: inserisce un `.CAS` (riavvolto all'inizio). Backspace la estrae.
- **Rewind cassette**: riavvolge la cassetta.
- **Eject cartridges & reset**: toglie le cartucce e riavvia.
- **System**: velocità CPU, RAM, drive sì/no, MSX-MUSIC sì/no, tastiera, ID del VDP, scambio joystick, slot della RAM (3-2 come sui Philips, predefinito, oppure 3-0 come sui Sony).
- **Cartridges**: mapper degli slot 1 e 2 (Auto o forzato).
- **Audio & Video**: volumi di PSG, SCC e FM, suono della cassetta, velocità cassetta, 50/60 Hz, tempi VGA per monitor CRT o LCD, barra di avanzamento della cassetta.
- **Reset**.

Quando cambi RAM, slot della RAM, mapper delle cartucce, drive o MSX-MUSIC l'MSX si riavvia da solo, perché su una macchina vera sono cambi di hardware.
Le altre voci hanno effetto subito.

Con le impostazioni di partenza (CPU 3,58 MHz, VDP V9938, 512 KB, drive attivo) il core si comporta come un MSX2 europeo con un drive.

## Preparare la SD

### 1. Il core
Copia `MSX2.rbf` sulla SD e caricalo dal menu dei core (o rinominalo `core.rbf` per farlo partire all'accensione).

### 2. Le ROM di sistema: il file `MSX2.ROM`
All'avvio il firmware della MiST carica da solo il file `MSX2.ROM` (dalla radice della SD o dalla cartella del core).
Ci sono tre modi per prepararlo.

**A) ROM di un MSX2 vero (consigliato).** Il file è l'unione di queste ROM, in quest'ordine:

| Offset | Dimensione | Contenuto | Obbligatorio |
|---|---|---|---|
| 0x00000 | 32 KB | MAIN-ROM (BIOS + MSX-BASIC) | sì |
| 0x08000 | 16 KB | SUB-ROM (MSX2 extended BIOS) | sì |
| 0x0C000 | 16 KB | DISK-ROM di tipo **Philips** (WD2793 a 7FF8h) | per usare i dischi |
| 0x10000 | 16 KB | MSX-MUSIC (FM-BIOS) | facoltativo |

Una scelta comoda è il **Philips NMS 8245**, che ha lo stesso controller disco emulato dal core.
Con i nomi dei file dei set di ROM di sistema di openMSX:

Windows (prompt dei comandi):
```
copy /b nms8245_basic-bios2.rom + nms8245_msx2sub.rom + nms8245_disk.rom MSX2.ROM
```
Linux / macOS:
```
cat nms8245_basic-bios2.rom nms8245_msx2sub.rom nms8245_disk.rom > MSX2.ROM
```

Vanno bene anche le DISK-ROM di Philips NMS 8250/8255/8280, VG-8235 e VY-0010, che usano lo stesso controller.
Quelle di altre marche (Sony, Panasonic, Toshiba…) usano registri diversi e **non** funzionano.
Per avere l'MSX-MUSIC aggiungi in coda una FM-BIOS da 16 KB (per esempio quella di un Panasonic FS-A1WX).

Le ROM possono anche stare in file separati: `MSX2.ROM` con la sola MAIN-ROM da 32 KB, poi `MSX2.R01` = SUB-ROM,
`MSX2.R02` = DISK-ROM, `MSX2.R03` = MSX-MUSIC. Il firmware li carica tutti all'avvio.

**B) Il BIOS che usi già con il core MSX attuale.** Puoi copiare il file `OCM-BIOS.DAT` (il BIOS MSX2+ di KdL) e rinominarlo `MSX2.ROM`:
il core ne prende MAIN-ROM, SUB-ROM e MSX-MUSIC. Quel BIOS non contiene una DISK-ROM per il controller Philips, quindi per i dischi
serve anche il file `MSX2.R02` con una DISK-ROM Philips da 16 KB. Con questo BIOS imposta *System → VDP ID → V9958 (MSX2+)*.
È una soluzione comoda per partire, ma il BIOS di KdL è pensato per la OneChipMSX: con un BIOS MSX2 vero il core è più fedele.

**C) Senza ROM originali** puoi usare il file `MSX2_CBIOS.ROM` incluso, rinominato `MSX2.ROM`. È C-BIOS, un BIOS libero che fa
partire solo le cartucce: niente BASIC, niente dischi e niente cassette.

Senza un `MSX2.ROM` valido lo schermo resta nero.

### 3. Giochi e programmi
Metti `.ROM`, `.DSK` e `.CAS` dove vuoi sulla SD, anche in sottocartelle, e caricali dal menu.

## Compilare il core

Serve **Quartus II 13.1** (Web Edition, gratuito): è la versione usata per i core MiST (il Cyclone III non è supportato dalle versioni più recenti).

1. Apri `mist/msx2_mist.qpf` in Quartus.
2. *Processing → Start Compilation*.
3. Alla fine trovi `mist/output_files/msx2_mist.rbf`. Rinominalo `MSX2.rbf` e copialo sulla SD.

I file per la scheda SiDi128 sono nella cartella `extra_sidi128` (vanno copiati in `mist/` e richiedono una versione di Quartus con il Cyclone 10 LP): non servono per la MiST.

Struttura dei sorgenti:

- `mist/MSX.sv`: top level per MiST, menu OSD, collegamento a user_io/data_io, dischi e cassetta
- `rtl/msx2_core.vhd`: il computer MSX2 (derivato da `emsx_top.vhd` dell'OCM): slot, controller SDRAM, mixer audio
- `rtl/rom_loader.vhd`: scrive ROM di sistema e cartucce nella SDRAM e riconosce il mapper
- `rtl/cart_slot.vhd`: mapper delle cartucce e SCC
- `rtl/msx_fdc.sv` + `rtl/wd1793.sv`: interfaccia disco Philips con WD2793 (wd1793 di Sorgelig)
- `rtl/cas_player.sv`: lettore di file .CAS che genera il segnale della cassetta
- `esemsx3/`: componenti OCM usati (VDP, PSG, OPLL, SCC, mapper, tastiera); `T80/`: CPU Z80
- `sim/`: banchi di prova per NVC (VHDL) e Verilator (SystemVerilog)

## Limiti noti

- Un solo drive (A:). Come sugli MSX con un drive solo, B: è il "drive fantasma" gestito dal DOS.
- Il comando WRITE TRACK del WD2793 non è emulato, quindi FORMAT non funziona: usa immagini .DSK già formattate.
- Sono supportate solo immagini .DSK a 9 settori per traccia (360/720 KB).
- I file .CAS con caricatori turbo non standard potrebbero non funzionare. Per la cassetta conviene la CPU a 3,58 MHz.
- Alcuni giochi (soprattutto versioni copiate o adattate) danno per scontato che la RAM sia in un certo slot: con la RAM in 3-2
  funzionano quelli pensati per i Philips (per esempio i caricatori con `POKE &HFFFF,&HAA`). Se un gioco si blocca o riavvia l'MSX,
  prova *System → RAM slot → 3-0 (Sony)*.
- Le cartucce con SRAM a batteria (per esempio Hydlide 2 o Xanadu) e i mapper rari (R-Type, Game Master 2, Zemina…) non sono supportati.

## Licenze

I componenti OCM (ESE Artists' factory, KdL, t.hara e altri) mantengono la loro licenza in stile BSD (vedi le intestazioni dei file).
T80 è di Daniel Wallner. wd1793.sv è di Sorgelig e Viacheslav Slavinsky (GPL). I moduli MiST sono di Till Harbaum e altri.
Il resto è distribuito sotto GPL v2 o successiva. C-BIOS: licenza BSD, vedi `cbios/LICENSE.txt`.
