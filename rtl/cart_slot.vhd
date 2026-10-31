--
-- cart_slot.vhd
--   ROM cartridge slot for the MSX2 MiST core.
--   The ROM image is stored in SDRAM (loaded by rom_loader through the
--   MiST OSD).  This module only translates the CPU address into an SDRAM
--   offset according to the selected mapper and generates the SCC sound
--   for Konami SCC cartridges.
--
--   Mapper types (mapper input):
--     0 : empty slot
--     1 : plain ROM (8-64 kB, no mapper), mapped at plain_base
--     2 : Konami with SCC   (banks 8K, regs 5000h/7000h/9000h/B000h)
--     3 : Konami without SCC (banks 8K, 4000h fixed, regs 6000h/8000h/A000h)
--     4 : ASCII 8K          (regs 6000h/6800h/7000h/7800h)
--     5 : ASCII 16K         (regs 6000h/7000h)
--     6 : Generic 8K        (write in a page selects its bank)
--
--   Mapper behaviour follows openMSX / fMSX.
--   Copyright (c) 2026 - released under the GNU GPL v2 or later.
--   The SCC address translation (SCC -> SCC-I/SCC+ register map) and the
--   channel D/E waveform sharing are taken from megaram.vhd (ESE MSX-SYSTEM3,
--   Copyright (c) 2006 Kazuhiro Tsujikawa, ESE Artists' factory).
--

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity cart_slot is
    port(
        clk21m      : in    std_logic;
        reset       : in    std_logic;
        clkena      : in    std_logic;                          -- 3.58MHz enable (SCC sound)
        req         : in    std_logic;                          -- access request (memory, this slot)
        ack         : out   std_logic;
        wrt         : in    std_logic;
        adr         : in    std_logic_vector( 15 downto 0 );
        dbi         : out   std_logic_vector(  7 downto 0 );    -- data to CPU
        dbo         : in    std_logic_vector(  7 downto 0 );    -- data from CPU

        ramreq      : out   std_logic;                          -- SDRAM read request
        ramadr      : out   std_logic_vector( 22 downto 0 );    -- offset inside the 8 MB cartridge area
        ramdbi      : in    std_logic_vector(  7 downto 0 );    -- data read from SDRAM

        mapper      : in    std_logic_vector(  2 downto 0 );    -- see table above (latched on reset)
        rom_mask    : in    std_logic_vector( 22 downto 0 );    -- 2^n-1 >= ROM size - 1
        rom_last    : in    std_logic_vector( 22 downto 0 );    -- ROM size - 1
        plain_base  : in    std_logic_vector(  1 downto 0 );    -- 16K page where a plain ROM starts

        wave        : out   std_logic_vector( 14 downto 0 )     -- SCC sound
    );
end cart_slot;

architecture rtl of cart_slot is

    component scc_wave
        port(
            clk21m  : in    std_logic;
            reset   : in    std_logic;
            clkena  : in    std_logic;
            req     : in    std_logic;
            ack     : out   std_logic;
            wrt     : in    std_logic;
            adr     : in    std_logic_vector( 7 downto 0);
            dbi     : out   std_logic_vector( 7 downto 0);
            dbo     : in    std_logic_vector( 7 downto 0);
            wave    : out   std_logic_vector(14 downto 0)
        );
    end component;

    constant M_NONE     : std_logic_vector(2 downto 0) := "000";
    constant M_PLAIN    : std_logic_vector(2 downto 0) := "001";
    constant M_KSCC     : std_logic_vector(2 downto 0) := "010";
    constant M_KONAMI   : std_logic_vector(2 downto 0) := "011";
    constant M_ASCII8   : std_logic_vector(2 downto 0) := "100";
    constant M_ASCII16  : std_logic_vector(2 downto 0) := "101";
    constant M_GEN8     : std_logic_vector(2 downto 0) := "110";

    signal ff_mapper    : std_logic_vector(2 downto 0) := M_NONE;

    -- bank registers (8K units, ASCII16 uses bank0/bank2 as 16K banks)
    signal bank0        : std_logic_vector(7 downto 0);
    signal bank1        : std_logic_vector(7 downto 0);
    signal bank2        : std_logic_vector(7 downto 0);
    signal bank3        : std_logic_vector(7 downto 0);

    signal w_page       : std_logic_vector(1 downto 0);         -- 16K page of the access
    signal w_in_rom     : std_logic;                            -- read hits the ROM area
    signal w_offset     : unsigned(22 downto 0);
    signal w_plain_off  : unsigned(15 downto 0);

    -- SCC
    signal w_scc_dec    : std_logic;
    signal WavReq       : std_logic;
    signal WavAck       : std_logic;
    signal WavCpy       : std_logic;
    signal WavAdr       : std_logic_vector(7 downto 0);
    signal WavDbi       : std_logic_vector(7 downto 0);
    signal SccAmp       : std_logic_vector(14 downto 0);

begin

    -- the mapper type can only change while the machine is in reset
    process( clk21m )
    begin
        if( rising_edge(clk21m) )then
            if( reset = '1' )then
                ff_mapper <= mapper;
            end if;
        end if;
    end process;

    w_page <= adr(15 downto 14);

    ----------------------------------------------------------------
    -- bank registers
    ----------------------------------------------------------------
    process( clk21m )
    begin
        if( rising_edge(clk21m) )then
            if( reset = '1' )then
                case mapper is
                    when M_ASCII8 | M_ASCII16 =>
                        bank0 <= X"00"; bank1 <= X"00"; bank2 <= X"00"; bank3 <= X"00";
                    when others =>
                        bank0 <= X"00"; bank1 <= X"01"; bank2 <= X"02"; bank3 <= X"03";
                end case;
            elsif( req = '1' and wrt = '1' )then
                case ff_mapper is
                    when M_KSCC =>
                        -- 5000-57FFh, 7000-77FFh, 9000-97FFh, B000-B7FFh
                        if( adr(12 downto 11) = "10" )then
                            case adr(15 downto 13) is
                                when "010"  => bank0 <= dbo;
                                when "011"  => bank1 <= dbo;
                                when "100"  => bank2 <= dbo;
                                when "101"  => bank3 <= dbo;
                                when others => null;
                            end case;
                        end if;
                    when M_KONAMI =>
                        -- 6000-7FFFh, 8000-9FFFh, A000-BFFFh (4000-5FFFh is fixed to bank 0)
                        case adr(15 downto 13) is
                            when "011"  => bank1 <= dbo;
                            when "100"  => bank2 <= dbo;
                            when "101"  => bank3 <= dbo;
                            when others => null;
                        end case;
                    when M_ASCII8 =>
                        if( adr(15 downto 12) = "0110" or adr(15 downto 12) = "0111" )then
                            case adr(12 downto 11) is
                                when "00"   => bank0 <= dbo;    -- 6000h
                                when "01"   => bank1 <= dbo;    -- 6800h
                                when "10"   => bank2 <= dbo;    -- 7000h
                                when others => bank3 <= dbo;    -- 7800h
                            end case;
                        end if;
                    when M_ASCII16 =>
                        if( adr(15 downto 11) = "01100" )then   -- 6000-67FFh
                            bank0 <= dbo;
                        elsif( adr(15 downto 11) = "01110" )then-- 7000-77FFh
                            bank2 <= dbo;
                        end if;
                    when M_GEN8 =>
                        case adr(15 downto 13) is
                            when "010"  => bank0 <= dbo;
                            when "011"  => bank1 <= dbo;
                            when "100"  => bank2 <= dbo;
                            when "101"  => bank3 <= dbo;
                            when others => null;
                        end case;
                    when others =>
                        null;
                end case;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- address translation
    ----------------------------------------------------------------
    w_plain_off <= unsigned(adr) - (unsigned(plain_base) & "00000000000000");

    process( ff_mapper, adr, w_page, bank0, bank1, bank2, bank3, w_plain_off, plain_base, rom_last )
        variable bank : std_logic_vector(7 downto 0);
    begin
        -- 8K bank of the region 4000-BFFFh
        case adr(15 downto 13) is
            when "010"  => bank := bank0;
            when "011"  => bank := bank1;
            when "100"  => bank := bank2;
            when others => bank := bank3;
        end case;

        w_in_rom <= '0';
        w_offset <= (others => '0');

        case ff_mapper is
            when M_PLAIN =>
                -- ROMs smaller than 16K are mirrored inside their 16K page
                if( unsigned(w_page) >= unsigned(plain_base) and
                    ( resize(w_plain_off, 23) <= unsigned(rom_last) or w_plain_off < to_unsigned(16#4000#, 16) ) )then
                    w_in_rom <= '1';
                end if;
                w_offset <= resize(w_plain_off, 23);

            when M_KSCC | M_KONAMI | M_ASCII8 | M_GEN8 =>
                if( w_page = "01" or w_page = "10" )then
                    w_in_rom <= '1';
                end if;
                if( ff_mapper = M_KONAMI and adr(15 downto 13) = "010" )then
                    bank := X"00";
                end if;
                w_offset <= resize(unsigned(bank) & unsigned(adr(12 downto 0)), 23);

            when M_ASCII16 =>
                if( w_page = "01" or w_page = "10" )then
                    w_in_rom <= '1';
                end if;
                if( w_page = "01" )then
                    w_offset <= resize(unsigned(bank0) & unsigned(adr(13 downto 0)), 23);
                else
                    w_offset <= resize(unsigned(bank2) & unsigned(adr(13 downto 0)), 23);
                end if;

            when others =>
                null;
        end case;
    end process;

    ramadr <= std_logic_vector(w_offset) and rom_mask;

    ----------------------------------------------------------------
    -- SCC (Konami SCC mapper, enabled by writing 3Fh to 9000h)
    -- registers in 9800-9FFFh (mirrored every 256 bytes)
    ----------------------------------------------------------------
    w_scc_dec <= '1' when( ff_mapper = M_KSCC and adr(15 downto 11) = "10011" and bank2(5 downto 0) = "111111" )else '0';

    WavReq  <= (req and w_scc_dec) or WavCpy;

    -- SCC register map -> SCC-I register map of scc_wave
    -- 9880-989F (freq/vol) <-> A0-BF, 98E0-98FF (deformation) <-> C0-DF
    WavAdr  <=  "100" & adr(4 downto 0)     when( WavCpy = '1' )else
                (adr(7 downto 0) xor X"20") when( adr(7) = '1' )else
                adr(7 downto 0);

    -- In the original SCC channel E shares the waveform of channel D:
    -- every write to 9860-987Fh is copied to the channel E wave memory.
    process( reset, clk21m )
        variable flag : std_logic;
    begin
        if( reset = '1' )then
            flag    := '0';
            WavCpy  <= '0';
        elsif( rising_edge(clk21m) )then
            if( WavReq = '1' and WavAck = '1' )then
                if( wrt = '1' and adr(7 downto 5) = "011" and w_scc_dec = '1' and flag = '0' )then
                    flag := '1';
                else
                    flag := '0';
                end if;
                WavCpy <= '0';
            elsif( flag = '1' and WavAck = '0' )then
                WavCpy <= '1';
            end if;
        end if;
    end process;

    SccCh : scc_wave
    port map(
        clk21m  => clk21m       ,
        reset   => reset        ,
        clkena  => clkena       ,
        req     => WavReq       ,
        ack     => WavAck       ,
        wrt     => wrt          ,
        adr     => WavAdr       ,
        dbi     => WavDbi       ,
        dbo     => dbo          ,
        wave    => SccAmp
    );

    wave <= SccAmp when( ff_mapper = M_KSCC )else (others => '0');

    ----------------------------------------------------------------
    -- bus
    ----------------------------------------------------------------
    ramreq  <=  req when( w_in_rom = '1' and w_scc_dec = '0' and wrt = '0' )else '0';

    ack     <=  WavAck  when( w_scc_dec = '1' )else
                req;

    dbi     <=  WavDbi  when( w_scc_dec = '1' )else
                ramdbi  when( w_in_rom = '1' )else
                (others => '1');

end rtl;
