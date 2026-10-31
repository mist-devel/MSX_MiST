# MSX1 per MiST

Versione MSX1 del core MSX2 per MiST (stessi sorgenti, compilati in modalità MSX1).
Si comporta come un MSX1 europeo con **64 KB di RAM fissa** (senza memory mapper), due slot per cartucce, drive per dischetti e registratore a cassette.
ROM, cartucce, dischetti e cassette si caricano dal menu OSD.

## Cosa fa

| Funzione | Dettagli |
|---|---|
| Slot | 0 = MAIN-ROM (BIOS + BASIC, 32 KB) (+ MSX-MUSIC in 0-2 se presente), 1 e 2 = cartucce, 3 = RAM 64 KB in uno slot non espanso, come sulla maggior parte degli MSX1. L'interfaccia disco si comporta come una cartuccia VY-0010 inserita nello slot 2 (vedi sotto) |
| RAM | 64 KB fissi, come un MSX1 (le porte del memory mapper FC-FFh non esistono) |
| Cartucce (.ROM) | Slot 1 e 2, mapper riconosciuto in automatico (ROM semplice, Konami, Konami SCC con suono SCC, ASCII 8K, ASCII 16K, Generic 8K) o forzato dal menu |
| Dischetti (.DSK) | Drive A:, immagini da 360 KB e 720 KB, lettura e scrittura |
| Cassette (.CAS) | `BLOAD"CAS:",R`, `RUN"CAS:"`, `CLOAD`, il nastro si muove solo con il motore acceso, 1200/2400 baud, barra di avanzamento sullo schermo durante il caricamento (disattivabile). Vanno bene anche i .CAS con i blocchi non allineati a 8 byte |
| Video | VDP compatibile TMS9918 (modi SCREEN 0-3 dell'MSX1) con i colori dell'MSX1, 50 Hz (PAL, predefinito) o 60 Hz, uscita 15 kHz o VGA |
| Audio | PSG, SCC (cartucce Konami), MSX-MUSIC facoltativo |
| CPU | Z80 a 3,58 MHz, con turbo opzionale fino a 10,74 MHz |
| Tastiera | Italiana (predefinita), US o giapponese |

Rispetto al core MSX2 mancano, come su un MSX1 vero: SUB-ROM, memory mapper, orologio RP-5C01, modi video MSX2.

**Il drive e lo slot 2.** Sugli MSX1 il drive era un'interfaccia da inserire in uno slot per cartucce (per esempio la Philips VY-0010).
Qui è "inserita" nello slot 2 quando lo slot 2 è vuoto: le cartucce mettile nello slot 1. Se carichi una cartuccia nello slot 2
il drive sparisce finché non la togli (*Eject cartridges & reset*), come se avessi sfilato l'interfaccia.

**RAM slot** (menu *System*): con *3 (normal)*, il valore predefinito, la RAM è in uno slot non espanso, come sulla maggior parte
degli MSX1. Con *3-2 (Philips)* lo slot 3 diventa espanso con la RAM nel sotto-slot 2, come sul Philips VG-8020: serve solo per
i rari programmi che lo richiedono.

## Il menu

Si apre con **F12**. Per aprirlo con **F11** aggiungi in fondo a `mist.ini`:

```
[MSX1]
key_remap=44,45
```

Voci: cartuccia slot 1 e 2, drive A:, cassetta, riavvolgi, estrai cartucce; *System* (CPU, drive, MSX-MUSIC, tastiera, joystick, RAM slot);
*Cartridges* (mapper); *Audio & Video* (volumi, cassetta, 50/60 Hz, VGA CRT/LCD, barra di avanzamento della cassetta); *Reset*.

## Preparare la SD

### 1. Il core
Copia `MSX1.rbf` sulla SD.

### 2. Le ROM di sistema: il file `MSX1.ROM`
All'avvio il firmware della MiST carica da solo `MSX1.ROM`. È l'unione di:

| Offset | Dimensione | Contenuto | Obbligatorio |
|---|---|---|---|
| 0x0000 | 32 KB | MAIN-ROM di un MSX1 (BIOS + MSX-BASIC) | sì |
| 0x8000 | 16 KB | DISK-ROM di tipo **Philips** (WD2793 a 7FF8h), per esempio quella del **VY-0010** | per usare i dischi |
| 0xC000 | 16 KB | MSX-MUSIC (FM-BIOS) | facoltativo |

Esempio con le ROM di un Philips VG-8020 e dell'interfaccia disco VY-0010 (i nomi dei file dipendono da dove le hai prese), su Windows:
```
copy /b vg8020_basic-bios1.rom + vy0010.rom MSX1.ROM
```
Linux / macOS:
```
cat vg8020_basic-bios1.rom vy0010.rom > MSX1.ROM
```

In alternativa: `MSX1.ROM` con la sola MAIN-ROM da 32 KB, `MSX1.R01` = DISK-ROM, `MSX1.R02` = MSX-MUSIC.

La DISK-ROM deve essere Philips (VY-0010, VG-8230/8235, NMS 8245/8250/8280): quelle Sony, Panasonic, Toshiba ecc. non funzionano.
Su un MSX1 la scelta più fedele è la VY-0010, che era proprio un'interfaccia disco per MSX1.

**Senza ROM originali** puoi provare il core con `cbios/MSX1_CBIOS.ROM` rinominato in `MSX1.ROM`: è C-BIOS, un BIOS libero che fa partire
solo le cartucce (niente BASIC, dischi e cassette).

Con un `MSX1.ROM` mancante o senza MAIN-ROM lo schermo resta nero.

### 3. Giochi e programmi
`.ROM`, `.DSK` e `.CAS` dove vuoi sulla SD, e si caricano dal menu.

## Compilare il core

Serve **Quartus II 13.1** con il supporto Cyclone III, come per il core MSX2.

1. Estrai lo zip in una cartella semplice (per esempio `C:\MSX1_MiST`).
2. Apri `mist\msx1_mist.qpf` e avvia *Processing → Start Compilation*.
3. Il risultato è `mist\output_files\msx1_mist.rbf`: rinominalo `MSX1.rbf` e copialo sulla SD.

Gli avvisi critici di timing (ritardi di pochi decimi di nanosecondo sulle uscite verso la SDRAM) e quelli del Design Assistant sono gli stessi
del core MSX2 e non impediscono il funzionamento.

## Limiti noti

- Il video è fatto con il VDP V9938 della OneChipMSX in modo compatibile TMS9918: i giochi MSX1 funzionano, ma alcuni effetti al limite
  dell'hardware (per esempio certi trucchi sugli sprite) possono comportarsi in modo leggermente diverso dal chip originale.
- Un solo drive (A:); FORMAT non funziona (usa immagini già formattate); solo .DSK a 9 settori per traccia.
- Niente cartucce con SRAM a batteria né mapper rari.
- Molti giochi su cassetta sono cartucce trasformate in file .CAS: copiano il gioco nella RAM della pagina 4000h-7FFFh e danno
  per scontato che la RAM stia in uno slot preciso. Con la RAM in uno slot non espanso (impostazione predefinita) funzionano sia
  quelli fatti per gli MSX1 comuni (per esempio Bubble) sia quelli con `POKE &HFFFF,&HAA` fatti per i Philips (per esempio HERO).

## Licenze

Come il core MSX2: componenti OCM con licenza in stile BSD, T80 di Daniel Wallner, wd1793.sv di Sorgelig (GPL), moduli MiST di Till Harbaum
e altri, il resto GPL v2 o successiva. C-BIOS: licenza BSD (`cbios/LICENSE.txt`).
