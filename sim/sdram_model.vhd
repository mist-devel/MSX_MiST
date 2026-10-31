--
-- sdram_model.vhd  -  behavioural SDRAM model for simulation only
--   32 MB, 4 banks x 8192 rows x 512 columns x 16 bit, CAS latency 2,
--   burst length 1, auto precharge.  Rows are allocated on first use.
--   Also counts the refresh commands (for checks in the testbench).
--
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use std.textio.all;

entity sdram_model is
    generic(
        -- backdoor preload (simulation speed-up): hex files, one byte per line
        INIT0_FILE  : string  := "";
        INIT0_BASE  : natural := 0;
        INIT1_FILE  : string  := "";
        INIT1_BASE  : natural := 0;
        INIT2_FILE  : string  := "";
        INIT2_BASE  : natural := 0;
        CHECK_MODE  : boolean := false          -- true: the files are compared when "check" rises
    );
    port(
        clk     : in    std_logic;
        cs_n    : in    std_logic;
        ras_n   : in    std_logic;
        cas_n   : in    std_logic;
        we_n    : in    std_logic;
        ba      : in    std_logic_vector(  1 downto 0 );
        a       : in    std_logic_vector( 12 downto 0 );
        dqm     : in    std_logic_vector(  1 downto 0 );    -- (1)=UDQM (0)=LDQM
        dq      : inout std_logic_vector( 15 downto 0 );
        refresh_count : out natural;
        check       : in    std_logic := '0'
    );
end sdram_model;

architecture sim of sdram_model is
    type row_t      is array (0 to 511) of integer range 0 to 65535;
    type row_ptr    is access row_t;
    type rows_t     is array (0 to 4*8192-1) of row_ptr;
begin

    process( clk, check )
        variable mem        : rows_t;
        variable open_row   : integer;
        type open_t is array (0 to 3) of integer;
        variable rows       : open_t := (others => 0);
        variable cmd        : std_logic_vector(3 downto 0);
        variable b, r, c    : integer;
        variable v          : integer;
        variable p          : row_ptr;
        variable rd_pipe1   : integer := -1;            -- data of a read, CL pipeline
        variable rd_pipe2   : integer := -1;
        variable rd_mask1   : std_logic_vector(1 downto 0);
        variable rd_mask2   : std_logic_vector(1 downto 0);
        variable rfsh       : natural := 0;
        variable wv         : unsigned(15 downto 0);
        variable loaded     : boolean := false;

        procedure poke( adr : natural; val : natural ) is
            variable ua  : unsigned(24 downto 0);
            variable rr  : integer;
            variable cc  : integer;
            variable w   : unsigned(15 downto 0);
        begin
            ua := to_unsigned(adr, 25);
            -- row = A24 A23 A11..A1, bank = A22 A21, column = A20..A12
            rr := to_integer(ua(22 downto 21)) * 8192 + to_integer(ua(24 downto 23) & ua(11 downto 1));
            cc := to_integer(ua(20 downto 12));
            if( mem(rr) = null )then
                mem(rr) := new row_t'(others => 0);
            end if;
            w := to_unsigned(mem(rr)(cc), 16);
            if( ua(0) = '0' )then
                w(7 downto 0) := to_unsigned(val, 8);
            else
                w(15 downto 8) := to_unsigned(val, 8);
            end if;
            mem(rr)(cc) := to_integer(w);
        end procedure;

        impure function peek( adr : natural ) return natural is
            variable ua  : unsigned(24 downto 0);
            variable rr  : integer;
            variable cc  : integer;
            variable w   : unsigned(15 downto 0);
        begin
            ua := to_unsigned(adr, 25);
            rr := to_integer(ua(22 downto 21)) * 8192 + to_integer(ua(24 downto 23) & ua(11 downto 1));
            cc := to_integer(ua(20 downto 12));
            if( mem(rr) = null )then return 256; end if;     -- never written
            w := to_unsigned(mem(rr)(cc), 16);
            if( ua(0) = '0' )then return to_integer(w(7 downto 0)); else return to_integer(w(15 downto 8)); end if;
        end function;

        procedure compare( fname : string; base : natural ) is
            file     f    : text;
            variable st   : file_open_status;
            variable l    : line;
            variable ch   : character;
            variable good : boolean;
            variable n    : natural;
            variable a    : natural := base;
            variable errs : natural := 0;
        begin
            if( fname'length = 0 )then return; end if;
            file_open(st, f, fname, read_mode);
            while not endfile(f) loop
                readline(f, l);
                n := 0;
                for k in 1 to 2 loop
                    read(l, ch, good);
                    if( ch >= '0' and ch <= '9' )then n := n*16 + character'pos(ch) - character'pos('0');
                    elsif( ch >= 'a' and ch <= 'f' )then n := n*16 + character'pos(ch) - character'pos('a') + 10;
                    else n := n*16 + character'pos(ch) - character'pos('A') + 10; end if;
                end loop;
                if( peek(a) /= n )then
                    if( errs < 5 )then
                        report "sdram_model: MISMATCH at " & integer'image(a) & " got " & integer'image(peek(a)) & " expected " & integer'image(n) severity error;
                    end if;
                    errs := errs + 1;
                end if;
                a := a + 1;
            end loop;
            file_close(f);
            report "sdram_model: compared " & fname & ": " & integer'image(a - base) & " bytes, " & integer'image(errs) & " errors";
        end procedure;

        procedure load( fname : string; base : natural ) is
            file     f    : text;
            variable st   : file_open_status;
            variable l    : line;
            variable ch   : character;
            variable good : boolean;
            variable n    : natural;
            variable a    : natural := base;
        begin
            if( fname'length = 0 )then return; end if;
            file_open(st, f, fname, read_mode);
            assert st = open_ok report "cannot open " & fname severity failure;
            while not endfile(f) loop
                readline(f, l);
                n := 0;
                for k in 1 to 2 loop
                    read(l, ch, good);
                    if( ch >= '0' and ch <= '9' )then n := n*16 + character'pos(ch) - character'pos('0');
                    elsif( ch >= 'a' and ch <= 'f' )then n := n*16 + character'pos(ch) - character'pos('a') + 10;
                    else n := n*16 + character'pos(ch) - character'pos('A') + 10; end if;
                end loop;
                poke(a, n);
                a := a + 1;
            end loop;
            file_close(f);
            report "sdram_model: preloaded " & fname & " (" & integer'image(a - base) & " bytes)";
        end procedure;
    begin
        if( not loaded )then
            if( not CHECK_MODE )then
                load(INIT0_FILE, INIT0_BASE);
                load(INIT1_FILE, INIT1_BASE);
                load(INIT2_FILE, INIT2_BASE);
            end if;
            loaded := true;
        end if;
        if( check'event and check = '1' )then
            compare(INIT0_FILE, INIT0_BASE);
            compare(INIT1_FILE, INIT1_BASE);
            compare(INIT2_FILE, INIT2_BASE);
        end if;
        if( rising_edge(clk) )then
            -- CAS latency pipeline: a read sampled at edge N drives DQ after edge N+1
            rd_pipe2 := rd_pipe1;
            rd_mask2 := rd_mask1;
            rd_pipe1 := -1;
            if( rd_pipe2 >= 0 )then
                wv := to_unsigned(rd_pipe2, 16);
                dq <= std_logic_vector(wv) after 1 ns;
            else
                dq <= (others => 'Z') after 1 ns;
            end if;

            cmd := cs_n & ras_n & cas_n & we_n;
            b := to_integer(unsigned(ba));
            case cmd is
                when "0011" =>                                  -- ACTIVATE
                    rows(b) := to_integer(unsigned(a));
                when "0101" =>                                  -- READ
                    r := b*8192 + rows(b);
                    c := to_integer(unsigned(a(8 downto 0)));
                    p := mem(r);
                    if( p = null )then
                        v := 0;
                    else
                        v := p(c);
                    end if;
                    rd_pipe1 := v;
                    rd_mask1 := dqm;
                when "0100" =>                                  -- WRITE
                    r := b*8192 + rows(b);
                    c := to_integer(unsigned(a(8 downto 0)));
                    if( mem(r) = null )then
                        mem(r) := new row_t'(others => 0);
                    end if;
                    p := mem(r);
                    wv := to_unsigned(p(c), 16);
                    if( dqm(0) = '0' )then
                        wv(7 downto 0)  := unsigned(to_x01(dq(7 downto 0)));
                    end if;
                    if( dqm(1) = '0' )then
                        wv(15 downto 8) := unsigned(to_x01(dq(15 downto 8)));
                    end if;
                    p(c) := to_integer(wv);
                when "0001" =>                                  -- AUTO REFRESH
                    rfsh := rfsh + 1;
                when others =>
                    null;
            end case;
            refresh_count <= rfsh;
        end if;
    end process;

end sim;
