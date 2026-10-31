--
-- rom_loader.vhd
--   Receives files from the MiST IO controller (data_io) and turns them
--   into a stream of SDRAM writes for the MSX2 core.
--
--   data_io index (ioctl_index[5:0]):
--     0 : MSX2.ROM  main BIOS (32K)  - may also be a combined image:
--                   MAIN(32K) + SUB(16K) + DISK(16K) [+ MSX-MUSIC(16K)]
--     1 : MSX2.R01  SUB ROM   (16K)
--     2 : MSX2.R02  DISK ROM  (16K, Philips/WD2793 type)
--     3 : MSX2.R03  MSX-MUSIC ROM (16K, optional)
--     7 : cartridge for slot 1   (OSD "F7")
--     8 : cartridge for slot 2   (OSD "F8")
--
--   SDRAM map (25 bit byte address):
--     0x0600000-0x061FFFF  system ROMs (offset 0x00000 main, 0x08000 sub,
--                          0x0C000 disk, 0x10000 MSX-MUSIC)
--     0x1000000-0x17FFFFF  cartridge slot 1 (max 8 MB)
--     0x1800000-0x1FFFFFF  cartridge slot 2 (max 8 MB)
--
--   For cartridges the loader also finds the mapper type with the
--   fMSX heuristic (counting "LD (nnnn),A" to known bank registers),
--   the ROM size and, for plain ROMs, the start address from the header.
--
--   Copyright (c) 2026 - released under the GNU GPL v2 or later.
--

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity rom_loader is
    generic(
        MSX1            : integer := 0                              -- 1: MSX1 file layout (MAIN, DISK, MSX-MUSIC)
    );
    port(
        clk21m          : in    std_logic;

        -- data_io
        dl_download     : in    std_logic;
        dl_index        : in    std_logic_vector(  7 downto 0 );
        dl_wr           : in    std_logic;
        dl_addr         : in    std_logic_vector( 26 downto 0 );
        dl_data         : in    std_logic_vector(  7 downto 0 );

        -- SDRAM write stream
        wr_req          : out   std_logic;                          -- one clock pulse per byte
        wr_adr          : out   std_logic_vector( 24 downto 0 );
        wr_dat          : out   std_logic_vector(  7 downto 0 );

        -- system ROMs present
        rom_main_ok     : out   std_logic;
        rom_sub_ok      : out   std_logic;
        rom_disk_ok     : out   std_logic;
        rom_music_ok    : out   std_logic;

        -- cartridges
        eject1          : in    std_logic;
        eject2          : in    std_logic;
        cart1_present   : out   std_logic;
        cart1_mapper    : out   std_logic_vector(  2 downto 0 );    -- detected mapper
        cart1_mask      : out   std_logic_vector( 22 downto 0 );
        cart1_last      : out   std_logic_vector( 22 downto 0 );
        cart1_base      : out   std_logic_vector(  1 downto 0 );
        cart2_present   : out   std_logic;
        cart2_mapper    : out   std_logic_vector(  2 downto 0 );
        cart2_mask      : out   std_logic_vector( 22 downto 0 );
        cart2_last      : out   std_logic_vector( 22 downto 0 );
        cart2_base      : out   std_logic_vector(  1 downto 0 )
    );
end rom_loader;

architecture rtl of rom_loader is

    constant M_PLAIN    : std_logic_vector(2 downto 0) := "001";
    constant M_KSCC     : std_logic_vector(2 downto 0) := "010";
    constant M_KONAMI   : std_logic_vector(2 downto 0) := "011";
    constant M_ASCII8   : std_logic_vector(2 downto 0) := "100";
    constant M_ASCII16  : std_logic_vector(2 downto 0) := "101";
    constant M_GEN8     : std_logic_vector(2 downto 0) := "110";

    type kind_t is (K_NONE, K_SYS, K_CART1, K_CART2);

    signal ff_dl        : std_logic := '0';
    signal ff_kind      : kind_t := K_NONE;
    signal ff_sysbase   : unsigned(16 downto 0) := (others => '0');
    signal ff_finish    : std_logic := '0';
    signal ff_ocm       : std_logic := '0';                         -- MSX2.ROM is an OCM-BIOS.DAT

    signal f_main       : std_logic := '0';
    signal f_sub        : std_logic := '0';
    signal f_disk       : std_logic := '0';
    signal f_music      : std_logic := '0';

    -- cartridge analysis
    signal ff_count     : unsigned(23 downto 0) := (others => '0');    -- bytes received
    signal ff_prev1     : std_logic_vector(7 downto 0) := (others => '0');
    signal ff_prev2     : std_logic_vector(7 downto 0) := (others => '0');
    signal c_scc        : unsigned(11 downto 0);
    signal c_k4         : unsigned(11 downto 0);
    signal c_a8         : unsigned(11 downto 0);
    signal c_a16        : unsigned(11 downto 0);
    type hdr_t is array (0 to 5) of std_logic_vector(7 downto 0);
    signal hdr0         : hdr_t;            -- bytes 0,1,2,3,8,9
    signal hdr1         : hdr_t;            -- bytes 4000h,4001h,4002h,4003h,4008h,4009h

    signal r1_present   : std_logic := '0';
    signal r1_mapper    : std_logic_vector(2 downto 0) := M_PLAIN;
    signal r1_mask      : std_logic_vector(22 downto 0) := (others => '1');
    signal r1_last      : std_logic_vector(22 downto 0) := (others => '1');
    signal r1_base      : std_logic_vector(1 downto 0) := "01";
    signal r2_present   : std_logic := '0';
    signal r2_mapper    : std_logic_vector(2 downto 0) := M_PLAIN;
    signal r2_mask      : std_logic_vector(22 downto 0) := (others => '1');
    signal r2_last      : std_logic_vector(22 downto 0) := (others => '1');
    signal r2_base      : std_logic_vector(1 downto 0) := "01";

    -- results of the analysis (combinational, valid when ff_finish = '1')
    signal w_last       : std_logic_vector(22 downto 0);
    signal w_mask       : std_logic_vector(22 downto 0);
    signal w_mapper     : std_logic_vector(2 downto 0);
    signal w_base       : std_logic_vector(1 downto 0);

    function inc_sat( c : unsigned ) return unsigned is
    begin
        if( c = (c'range => '1') )then
            return c;
        else
            return c + 1;
        end if;
    end function;

    -- 16K page from a Z80 address stored in a ROM header (lo, hi bytes)
    function hdr_page( lo, hi : std_logic_vector(7 downto 0) ) return std_logic_vector is
    begin
        return hi(7 downto 6);
    end function;

begin

    ----------------------------------------------------------------
    -- download handling
    ----------------------------------------------------------------
    process( clk21m )
        variable idx    : unsigned(5 downto 0);
        variable a      : unsigned(22 downto 0);
        variable sa     : unsigned(17 downto 0);
        variable w      : std_logic_vector(23 downto 0);
        variable sys_ok : boolean;
    begin
        if( rising_edge(clk21m) )then
            wr_req    <= '0';
            ff_finish <= '0';
            ff_dl     <= dl_download;

            -- start of a download
            if( dl_download = '1' and ff_dl = '0' )then
                idx := unsigned(dl_index(5 downto 0));
                ff_count <= (others => '0');
                c_scc <= (others => '0');
                c_k4  <= (others => '0');
                c_a8  <= (others => '0');
                c_a16 <= (others => '0');
                ff_prev1 <= (others => '0');
                ff_prev2 <= (others => '0');
                hdr0 <= (others => (others => '0'));
                hdr1 <= (others => (others => '0'));
                ff_ocm <= '0';
                case to_integer(idx) is
                    when 0 =>
                        ff_kind <= K_SYS;  ff_sysbase <= to_unsigned(16#00000#, 17);
                        f_main <= '0'; f_sub <= '0'; f_disk <= '0'; f_music <= '0';
                    when 1 =>                                       -- MSX2: SUB, MSX1: DISK
                        ff_kind <= K_SYS;
                        if( MSX1 /= 0 )then ff_sysbase <= to_unsigned(16#0C000#, 17);
                        else                ff_sysbase <= to_unsigned(16#08000#, 17); end if;
                    when 2 =>                                       -- MSX2: DISK, MSX1: MSX-MUSIC
                        ff_kind <= K_SYS;
                        if( MSX1 /= 0 )then ff_sysbase <= to_unsigned(16#10000#, 17);
                        else                ff_sysbase <= to_unsigned(16#0C000#, 17); end if;
                    when 3 =>
                        ff_kind <= K_SYS;  ff_sysbase <= to_unsigned(16#10000#, 17);
                    when 7 =>
                        ff_kind <= K_CART1; r1_present <= '0';
                    when 8 =>
                        ff_kind <= K_CART2; r2_present <= '0';
                    when others =>
                        ff_kind <= K_NONE;
                end case;
            end if;

            -- end of a download
            if( dl_download = '0' and ff_dl = '1' )then
                ff_finish <= '1';
            end if;

            -- data byte
            if( dl_download = '1' and dl_wr = '1' )then
                a := unsigned(dl_addr(22 downto 0));
                case ff_kind is
                    when K_SYS =>
                        sa := resize(ff_sysbase, 18) + resize(a(16 downto 0), 18);
                        -- OCM-BIOS.DAT (1chipMSX / OCM, 384-512 kB) as MSX2.ROM: take the
                        -- MAIN-ROM (20000h), MSX-MUSIC (2C000h) and SUB-ROM (30000h)
                        sys_ok := ( dl_addr(26 downto 17) = "0000000000" );
                        -- MSX1: MSX1.ROM = MAIN(32K) + DISK(16K) [+ MSX-MUSIC(16K)]
                        if( MSX1 /= 0 and ff_sysbase = 0 )then
                            case dl_addr(16 downto 14) is
                                when "000" | "001" => null;                                 -- MAIN
                                when "010"  => sa := "00" & "11" & a(13 downto 0);          -- DISK
                                when "011"  => sa := "01" & "00" & a(13 downto 0);          -- MSX-MUSIC
                                when others => sys_ok := false;
                            end case;
                        end if;
                        if( MSX1 = 0 and ff_sysbase = 0 and dl_addr(26 downto 17) = "0000000001" )then
                            ff_ocm <= '1';
                            sys_ok := true;
                            case dl_addr(16 downto 14) is
                                when "000"  => sa := "00" & "00" & a(13 downto 0);   -- MAIN 1st half
                                when "001"  => sa := "00" & "01" & a(13 downto 0);   -- MAIN 2nd half
                                when "011"  => sa := "01" & "00" & a(13 downto 0);   -- MSX-MUSIC
                                when "100"  => sa := "00" & "10" & a(13 downto 0);   -- SUB
                                when others => sys_ok := false;                      -- not used
                            end case;
                        end if;
                        if( sys_ok and sa(17) = '0' )then
                            wr_req <= '1';
                            wr_adr <= "0011000" & std_logic_vector(sa);    -- 0x0600000 + sa
                            wr_dat <= dl_data;
                            case sa(16 downto 14) is
                                when "000" | "001" => f_main  <= '1';
                                when "010"         => f_sub   <= '1';
                                when "011"         => f_disk  <= '1';
                                when "100"         => f_music <= '1';
                                when others        => null;
                            end case;
                        end if;

                    when K_CART1 | K_CART2 =>
                        if( dl_addr(26 downto 23) = "0000" )then
                            wr_req <= '1';
                            if( ff_kind = K_CART1 )then
                                wr_adr <= "10" & std_logic_vector(a);
                            else
                                wr_adr <= "11" & std_logic_vector(a);
                            end if;
                            wr_dat <= dl_data;
                            ff_count <= resize(a, 24) + 1;

                            -- header bytes
                            if( a(22 downto 4) = 0 )then
                                case to_integer(a(3 downto 0)) is
                                    when 0 => hdr0(0) <= dl_data;
                                    when 1 => hdr0(1) <= dl_data;
                                    when 2 => hdr0(2) <= dl_data;
                                    when 3 => hdr0(3) <= dl_data;
                                    when 8 => hdr0(4) <= dl_data;
                                    when 9 => hdr0(5) <= dl_data;
                                    when others => null;
                                end case;
                            elsif( a(22 downto 4) = to_unsigned(16#400#, 19) )then
                                case to_integer(a(3 downto 0)) is
                                    when 0 => hdr1(0) <= dl_data;
                                    when 1 => hdr1(1) <= dl_data;
                                    when 2 => hdr1(2) <= dl_data;
                                    when 3 => hdr1(3) <= dl_data;
                                    when 8 => hdr1(4) <= dl_data;
                                    when 9 => hdr1(5) <= dl_data;
                                    when others => null;
                                end case;
                            end if;

                            -- mapper detection: LD (nnnn),A = 32h lo hi
                            ff_prev2 <= ff_prev1;
                            ff_prev1 <= dl_data;
                            w := ff_prev2 & ff_prev1 & dl_data;
                            case w is
                                when X"320050" | X"320090" | X"3200B0" =>
                                    c_scc <= inc_sat(c_scc);
                                when X"320040" | X"320080" | X"3200A0" =>
                                    c_k4  <= inc_sat(c_k4);
                                when X"320068" | X"320078" =>
                                    c_a8  <= inc_sat(c_a8);
                                when X"320060" =>
                                    c_k4  <= inc_sat(c_k4);
                                    c_a8  <= inc_sat(c_a8);
                                    c_a16 <= inc_sat(c_a16);
                                when X"320070" =>
                                    c_scc <= inc_sat(c_scc);
                                    c_a8  <= inc_sat(c_a8);
                                    c_a16 <= inc_sat(c_a16);
                                when X"32FF77" =>
                                    c_a16 <= inc_sat(c_a16);
                                when others =>
                                    null;
                            end case;
                        end if;

                    when others =>
                        null;
                end case;
            end if;

            -- store the analysis result
            if( ff_finish = '1' )then
                -- OCM-BIOS.DAT: its first 128 kB (MegaSD driver) were written over the
                -- disk ROM area, a Philips disk ROM must come from MSX2.R02
                if( ff_kind = K_SYS and ff_ocm = '1' )then
                    f_disk <= '0';
                end if;
                if( ff_kind = K_CART1 and ff_count /= 0 )then
                    r1_present <= '1';
                    r1_mapper  <= w_mapper;
                    r1_mask    <= w_mask;
                    r1_last    <= w_last;
                    r1_base    <= w_base;
                elsif( ff_kind = K_CART2 and ff_count /= 0 )then
                    r2_present <= '1';
                    r2_mapper  <= w_mapper;
                    r2_mask    <= w_mask;
                    r2_last    <= w_last;
                    r2_base    <= w_base;
                end if;
                ff_kind <= K_NONE;
            end if;

            -- OSD eject
            if( eject1 = '1' )then
                r1_present <= '0';
            end if;
            if( eject2 = '1' )then
                r2_present <= '0';
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- analysis of the received cartridge
    ----------------------------------------------------------------
    w_last <= std_logic_vector(resize(ff_count - 1, 23)) when( ff_count(23) = '0' )else (others => '1');

    -- smallest 2^n-1 that covers the ROM (minimum 8 kB)
    process( w_last )
        variable m : std_logic_vector(22 downto 0);
    begin
        m := w_last;
        for i in 21 downto 0 loop
            m(i) := m(i) or m(i+1);
        end loop;
        m(12 downto 0) := (others => '1');
        w_mask <= m;
    end process;

    -- mapper: plain up to 64 kB, otherwise the most likely one (fMSX)
    process( ff_count, c_scc, c_k4, c_a8, c_a16 )
        variable best   : unsigned(11 downto 0);
        variable m      : std_logic_vector(2 downto 0);
    begin
        if( ff_count <= to_unsigned(65536, 24) )then
            w_mapper <= M_PLAIN;
        else
            best := (others => '0');
            m    := M_GEN8;
            if( c_scc > best )then best := c_scc; m := M_KSCC;    end if;
            if( c_k4  > best )then best := c_k4;  m := M_KONAMI;  end if;
            if( c_a8  > best )then best := c_a8;  m := M_ASCII8;  end if;
            if( c_a16 > best )then best := c_a16; m := M_ASCII16; end if;
            w_mapper <= m;
        end if;
    end process;

    -- start page of a plain ROM, from the "AB" header
    process( hdr0, hdr1, ff_count )
        variable p : std_logic_vector(1 downto 0);
    begin
        w_base <= "01";                                         -- default 4000h
        if( hdr0(0) = X"41" and hdr0(1) = X"42" )then           -- "AB" at the start
            if( hdr0(2) /= X"00" or hdr0(3) /= X"00" )then
                p := hdr_page(hdr0(2), hdr0(3));                -- INIT address
            else
                p := hdr_page(hdr0(4), hdr0(5));                -- BASIC text address
            end if;
            if( p = "10" and ff_count <= to_unsigned(16#4000#, 24) )then
                w_base <= "10";                                 -- 8000h (only 16K ROMs fit there)
            end if;
        elsif( ff_count > to_unsigned(16#4000#, 24) and hdr1(0) = X"41" and hdr1(1) = X"42" )then
            if( hdr1(2) /= X"00" or hdr1(3) /= X"00" )then
                p := hdr_page(hdr1(2), hdr1(3));
            else
                p := hdr_page(hdr1(4), hdr1(5));
            end if;
            if( p = "01" )then
                w_base <= "00";                                 -- ROM starts at 0000h
            end if;
        end if;
    end process;

    rom_main_ok     <= f_main;
    rom_sub_ok      <= f_sub;
    rom_disk_ok     <= f_disk;
    rom_music_ok    <= f_music;

    cart1_present   <= r1_present;
    cart1_mapper    <= r1_mapper;
    cart1_mask      <= r1_mask;
    cart1_last      <= r1_last;
    cart1_base      <= r1_base;
    cart2_present   <= r2_present;
    cart2_mapper    <= r2_mapper;
    cart2_mask      <= r2_mask;
    cart2_last      <= r2_last;
    cart2_base      <= r2_base;

end rtl;
