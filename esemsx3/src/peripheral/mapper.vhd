--
-- mapper.vhd
--   Memory mapper
--   Revision 1.00
--
-- Copyright (c) 2006 Kazuhiro Tsujikawa (ESE Artists' factory)
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

-- 2026: MSX2 MiST - added selectable mapper size (64 kB .. 4 MB).
--   The unused bits of the page registers read back as '1' and the
--   memory is mirrored, like on a real memory mapper.
--   size: "000"=512K "001"=1M "010"=2M "011"=4M "100"=128K "101"=256K
--         "110"/"111"=64K

entity mapper is
  port(
    clk21m  : in std_logic;
    reset   : in std_logic;
    clkena  : in std_logic;
    req     : in std_logic;
    ack     : out std_logic;
    mem     : in std_logic;
    wrt     : in std_logic;
    adr     : in std_logic_vector(15 downto 0);
    dbi     : out std_logic_vector(7 downto 0);
    dbo     : in std_logic_vector(7 downto 0);

    size    : in std_logic_vector(2 downto 0);

    ramreq  : out std_logic;
    ramwrt  : out std_logic;
    ramadr  : out std_logic_vector(21 downto 0);
    ramdbi  : in std_logic_vector(7 downto 0);
    ramdbo  : out std_logic_vector(7 downto 0)
  );
end mapper;

architecture rtl of mapper is

  signal MapBank0    : std_logic_vector(7 downto 0);
  signal MapBank1    : std_logic_vector(7 downto 0);
  signal MapBank2    : std_logic_vector(7 downto 0);
  signal MapBank3    : std_logic_vector(7 downto 0);
  signal PageMask    : std_logic_vector(7 downto 0) := X"1F";
  signal Bank        : std_logic_vector(7 downto 0);

begin

  -- the size can change only while the machine is in reset
  process(clk21m)
  begin
    if (clk21m'event and clk21m = '1') then
      if (reset = '1') then
        case size is
          when "000"  => PageMask <= X"1F";   --  512 kB
          when "001"  => PageMask <= X"3F";   -- 1024 kB
          when "010"  => PageMask <= X"7F";   -- 2048 kB
          when "011"  => PageMask <= X"FF";   -- 4096 kB
          when "100"  => PageMask <= X"07";   --  128 kB
          when "101"  => PageMask <= X"0F";   --  256 kB
          when others => PageMask <= X"03";   --   64 kB
        end case;
      end if;
    end if;
  end process;

  process(clk21m, reset)

  begin

    if (reset = '1') then

      MapBank0   <= X"03";
      MapBank1   <= X"02";
      MapBank2   <= X"01";
      MapBank3   <= X"00";

    elsif (clk21m'event and clk21m = '1') then

      if (req = '1' and mem = '0' and wrt = '1') then
        case adr(1 downto 0) is
          when "00"   => MapBank0 <= dbo;
          when "01"   => MapBank1 <= dbo;
          when "10"   => MapBank2 <= dbo;
          when others => MapBank3 <= dbo;
        end case;
      end if;

    end if;

  end process;

  ack    <= req when mem = '0' else '0';

  RamReq <= req when mem = '1' else '0';
  RamWrt <= wrt;

  Bank   <= MapBank0 when adr(15 downto 14) = "00" else
            MapBank1 when adr(15 downto 14) = "01" else
            MapBank2 when adr(15 downto 14) = "10" else
            MapBank3;

  RamAdr <= (Bank and PageMask) & adr(13 downto 0);

  RamDbo <= dbo;
  dbi    <= RamDbi   when mem = '1'              else
            (MapBank0 or not PageMask) when adr(1 downto 0) = "00" else
            (MapBank1 or not PageMask) when adr(1 downto 0) = "01" else
            (MapBank2 or not PageMask) when adr(1 downto 0) = "10" else
            (MapBank3 or not PageMask);

end rtl;
