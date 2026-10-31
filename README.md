# MSX2 e MSX1 per MiST, con menu OSD

Questo ramo (`msx2-msx1-osd`) parte dal core OneChipMSX per MiST di gyurco ([gyurco/MSX_MiST](https://github.com/gyurco/MSX_MiST))
e lo trasforma in due core che si comportano come computer MSX veri e si usano dal menu della MiST (F12, o F11 con `key_remap`):

- **MSX2** (`mist/msx2_mist.qpf`): MAIN-ROM, SUB-ROM, memory mapper 64 KB–4 MB, RTC, VDP V9938/V9958.
- **MSX1** (`mist/msx1_mist.qpf`): 64 KB di RAM fissa in uno slot non espanso, niente SUB-ROM, mapper e RTC,
  interfaccia disco come una cartuccia VY-0010 nello slot 2.

In comune:

- niente SD virtuale, VHD o hard disk;
- cartucce `.ROM` negli slot 1 e 2 con riconoscimento automatico del mapper (Konami, Konami SCC, ASCII 8K/16K, Generic 8K);
- drive A: con immagini `.DSK` da 360/720 KB (controller WD2793 tipo Philips);
- cassetta `.CAS` caricata con `BLOAD"CAS:",R`, `RUN"CAS:"` e `CLOAD`, con barra di avanzamento sullo schermo;
- velocità della CPU, volumi di PSG, SCC e FM, 50/60 Hz, tastiera italiana, US o giapponese.

Le istruzioni (preparazione delle ROM, uso del menu, compilazione con Quartus II 13.1) sono in
[LEGGIMI.md](LEGGIMI.md) per l'MSX2 e in [LEGGIMI_MSX1.md](LEGGIMI_MSX1.md) per l'MSX1.

I sottomoduli `T80` e `mist/mist-modules` vanno scaricati prima di compilare:

```
git clone --recursive -b msx2-msx1-osd https://github.com/ivan0174-hue/MSX_MiST.git
```

Il ramo `master` contiene il core originale, senza modifiche.

## Licenze

I componenti OCM (ESE Artists' factory, KdL, t.hara e altri) mantengono la loro licenza in stile BSD.
T80 è di Daniel Wallner. `rtl/wd1793.sv` è di Sorgelig e Viacheslav Slavinsky (GPL). I moduli MiST sono di Till Harbaum e altri.
Il resto è distribuito sotto GPL v2 o successiva. C-BIOS: licenza BSD (`cbios/LICENSE.txt`).
