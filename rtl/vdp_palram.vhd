--
-- vdp_palram.vhd
--   Palette memory of the VDP with initial content (MSX2/MSX1 MiST cores).
--
--   Same interface as ram.vhd, but the 16 palette entries start with the
--   "MSX1 like" colours that the OCM IPL-ROM used to write before starting
--   the BIOS. An MSX1 BIOS never writes the palette, so without this the
--   screen would stay black; an MSX2 BIOS overwrites the table anyway.
--
--   G_TABLE = false : byte 0RRR0BBB, G_TABLE = true : byte 00000GGG
--
--   Copyright (c) 2026 - released under the GNU GPL v2 or later.
--   Colour table from the OCM IPL-ROM v3 (t.hara, KdL).
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity vdp_palram is
  generic (
    G_TABLE : boolean := false
  );
  port (
    adr     : in  std_logic_vector(7 downto 0);
    clk     : in  std_logic;
    we      : in  std_logic;
    dbo     : in  std_logic_vector(7 downto 0);
    dbi     : out std_logic_vector(7 downto 0)
  );
end vdp_palram;

architecture RTL of vdp_palram is
  type typram is array (0 to 255) of std_logic_vector(7 downto 0);

  --                    0      1      2      3      4      5      6      7
  --                    8      9     10     11     12     13     14     15
  constant c_rb : typram := (
                      X"00", X"00", X"22", X"34", X"37", X"47", X"53", X"47",
                      X"63", X"64", X"63", X"65", X"11", X"56", X"66", X"77",
                      others => X"00" );
  constant c_g  : typram := (
                      X"00", X"00", X"06", X"07", X"03", X"04", X"03", X"06",
                      X"03", X"04", X"06", X"06", X"05", X"03", X"06", X"07",
                      others => X"00" );

  function init return typram is
  begin
    if( G_TABLE )then
      return c_g;
    else
      return c_rb;
    end if;
  end function;

  signal blkram : typram := init;
  signal iadr   : std_logic_vector(7 downto 0) := (others => '0');

begin

  process (clk)
  begin
    if (clk'event and clk = '1') then
      if (we = '1') then
        blkram(conv_integer(adr)) <= dbo;
      end if;
      iadr <= adr;
    end if;
  end process;

  dbi <= blkram(conv_integer(iadr));

end RTL;
