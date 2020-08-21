--
-- rtc.vhd
--   REAL TIME CLOCK (MSX2 CLOCK-IC)
--   Version 1.00
--
-- Copyright (c) 2008 Takayuki Hara
-- All rights reserved.
--
-- Redistribution and use of this source code or any derivative works, are
-- permitted provided that the following conditions are met:
--
-- 1. Redistributions of source code must retain the above copyright notice,
--    this list of conditions and the following disclaimer.
-- 2. Redistributions in binary form must reproduce the above copyright
--    notice, this list of conditions and the following disclaimer in the
--    documentation and/or other materials provided with the distribution.
-- 3. Redistributions may not be sold, nor may they be used in a commercial
--    product or activity without specific prior written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
-- "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
-- TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
-- CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
-- EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
-- PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
-- OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
-- WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
-- OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
-- ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.std_logic_unsigned.all;

entity rtc_mist is
    port(
        clk21m      : in    std_logic;
        reset       : in    std_logic;
        rtc         : in    std_logic_vector(63 downto 0);
        req         : in    std_logic;
        ack         : out   std_logic;
        wrt         : in    std_logic;
        adr         : in    std_logic_vector( 15 downto 0 );
        dbi         : out   std_logic_vector(  7 downto 0 );
        dbo         : in    std_logic_vector(  7 downto 0 )
 );
end rtc_mist;

architecture rtl of rtc_mist is

    -- bank memory
    component ram is
        port (
            adr     : in    std_logic_vector( 7 downto 0 );
            clk     : in    std_logic;
            we      : in    std_logic;
            dbo     : in    std_logic_vector( 7 downto 0 );
            dbi     : out   std_logic_vector( 7 downto 0 )
        );
    end component;

    -- ff
    signal ff_req       : std_logic;
    signal ff_1sec_cnt  : std_logic_vector(  3 downto 0 );

    -- register ff
    signal reg_ptr      : std_logic_vector(  3 downto 0 );
    signal reg_mode     : std_logic_vector(  3 downto 0 );      --  te, ae(not supported), m1, m0
    signal reg_sec_l    : std_logic_vector(  3 downto 0 );      --  hl = x"00" ... x"59"
    signal reg_sec_h    : std_logic_vector(  6 downto 4 );
    signal reg_min_l    : std_logic_vector(  3 downto 0 );      --  hl = x"00" ... x"59"
    signal reg_min_h    : std_logic_vector(  6 downto 4 );
    signal reg_hou_l    : std_logic_vector(  3 downto 0 );      --  hl = x"00" ... x"23"
    signal reg_hou_h    : std_logic_vector(  5 downto 4 );      --  hl = x"00" ... x"23"
    signal reg_wee      : std_logic_vector(  2 downto 0 );      --       x"0"  ... x"6"
    signal reg_day_l    : std_logic_vector(  3 downto 0 );      --  hl = x"00" ... x"31"
    signal reg_day_h    : std_logic_vector(  5 downto 4 );      --
    signal reg_mon_l    : std_logic_vector(  3 downto 0 );      --  hl = x"01" ... x"12"
    signal reg_mon_h    : std_logic;
    signal reg_yea_l    : std_logic_vector(  3 downto 0 );      --  hl = x"00" ... x"99"
    signal reg_yea_h    : std_logic_vector(  7 downto 4 );
    signal reg_1224     : std_logic;                            --  '0' = 12hour mode, '1' = 24hour mode
    signal reg_leap     : std_logic_vector(  1 downto 0 );      --  "00" leap year, "01" ... "11" other year

    -- wire
    signal w_adr_dec    : std_logic_vector( 15 downto 0 );
    signal w_bank_dec   : std_logic_vector(  2 downto 0 );
    signal w_wrt        : std_logic;
    signal w_mem_we     : std_logic;
    signal w_mem_addr   : std_logic_vector(  7 downto 0 );
    signal w_mem_q      : std_logic_vector(  7 downto 0 );
begin

    ----------------------------------------------------------------
    -- address decoder
    ----------------------------------------------------------------
    with reg_ptr select w_adr_dec <=
        "0000000000000001" when "0000",
        "0000000000000010" when "0001",
        "0000000000000100" when "0010",
        "0000000000001000" when "0011",
        "0000000000010000" when "0100",
        "0000000000100000" when "0101",
        "0000000001000000" when "0110",
        "0000000010000000" when "0111",
        "0000000100000000" when "1000",
        "0000001000000000" when "1001",
        "0000010000000000" when "1010",
        "0000100000000000" when "1011",
        "0001000000000000" when "1100",
        "0010000000000000" when "1101",
        "0100000000000000" when "1110",
        "1000000000000000" when "1111",
        "XXXXXXXXXXXXXXXX" when others;

    with reg_mode( 1 downto 0 ) select w_bank_dec <=
        "001" when "00",
        "010" when "01",
        "100" when "10",
        "100" when "11",
        "XXX" when others;

    w_wrt <= req and wrt;

    ----------------------------------------------------------------
    -- rtc register read
    ----------------------------------------------------------------
    dbi <=  "1111"    & reg_mode            when(                         w_adr_dec(13) = '1' and adr(0) = '1' )else
            "1111"    & reg_sec_l           when( w_bank_dec(0) = '1' and w_adr_dec( 0) = '1' and adr(0) = '1' )else
            "11110"   & reg_sec_h           when( w_bank_dec(0) = '1' and w_adr_dec( 1) = '1' and adr(0) = '1' )else
            "1111"    & reg_min_l           when( w_bank_dec(0) = '1' and w_adr_dec( 2) = '1' and adr(0) = '1' )else
            "11110"   & reg_min_h           when( w_bank_dec(0) = '1' and w_adr_dec( 3) = '1' and adr(0) = '1' )else
            "1111"    & reg_hou_l           when( w_bank_dec(0) = '1' and w_adr_dec( 4) = '1' and adr(0) = '1' )else
            "111100"  & reg_hou_h           when( w_bank_dec(0) = '1' and w_adr_dec( 5) = '1' and adr(0) = '1' )else
            "11110"   & reg_wee             when( w_bank_dec(0) = '1' and w_adr_dec( 6) = '1' and adr(0) = '1' )else
            "1111"    & reg_day_l           when( w_bank_dec(0) = '1' and w_adr_dec( 7) = '1' and adr(0) = '1' )else
            "111100"  & reg_day_h           when( w_bank_dec(0) = '1' and w_adr_dec( 8) = '1' and adr(0) = '1' )else
            "1111"    & reg_mon_l           when( w_bank_dec(0) = '1' and w_adr_dec( 9) = '1' and adr(0) = '1' )else
            "1111000" & reg_mon_h           when( w_bank_dec(0) = '1' and w_adr_dec(10) = '1' and adr(0) = '1' )else
            "1111"    & reg_yea_l           when( w_bank_dec(0) = '1' and w_adr_dec(11) = '1' and adr(0) = '1' )else
            "1111"    & reg_yea_h           when( w_bank_dec(0) = '1' and w_adr_dec(12) = '1' and adr(0) = '1' )else
            "111100"  & reg_leap            when( w_bank_dec(1) = '1' and w_adr_dec(11) = '1' and adr(0) = '1' )else
            "1111"    & w_mem_q(3 downto 0) when( w_bank_dec(2) = '1'                         and adr(0) = '1' )else
            (others => '1');

    reg_sec_l <= rtc(3 downto 0);
    reg_sec_h <= rtc(6 downto 4);
    reg_min_l <= rtc(11 downto 8);
    reg_min_h <= rtc(14 downto 12);
    reg_hou_l <= rtc(19 downto 16);
    reg_hou_h <= rtc(21 downto 20);
    reg_wee   <= rtc(47 downto 45);
    reg_day_l <= rtc(27 downto 24);
    reg_day_h <= rtc(29 downto 28);
    reg_mon_l <= rtc(35 downto 32);
    reg_mon_h <= rtc(36);
    reg_yea_l <= rtc(43 downto 40);
    reg_yea_h <= rtc(47 downto 44) + "10";

    ----------------------------------------------------------------
    -- request and ack
    ----------------------------------------------------------------
    process( reset, clk21m )
    begin
        if( reset = '1' )then
            ff_req <= '0';
        elsif( clk21m'event and clk21m = '1' )then
            ff_req <= req;
        end if;
    end process;

    ack <= ff_req;

    ----------------------------------------------------------------
    -- rtc register pointer
    ----------------------------------------------------------------
    process( reset, clk21m )
    begin
        if( reset = '1' )then
            reg_ptr <= (others => '0');
        elsif( clk21m'event and clk21m = '1' )then
            if( w_wrt = '1' and adr(0) = '0' )then
                -- register pointer
                reg_ptr <= dbo(3 downto 0);
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- rtc test register
    ----------------------------------------------------------------
    process( reset, clk21m )
    begin
        if( reset = '1' )then
            reg_mode        <= "1000";
        elsif( clk21m'event and clk21m = '1' )then
            if( w_wrt = '1' and adr(0) = '1' and w_adr_dec(13) = '1' )then
                reg_mode <= dbo(3 downto 0);
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- backup memory emulation
    ----------------------------------------------------------------
    w_mem_addr  <= "00" & reg_mode(1 downto 0) & reg_ptr;
    w_mem_we    <=  '1' when( w_wrt = '1' and adr(0) = '1' )else
                '0';

    u_mem: ram
    port map (
        adr     => w_mem_addr   ,
        clk     => clk21m       ,
        we      => w_mem_we     ,
        dbo     => dbo          ,
        dbi     => w_mem_q
    );

end rtl;
