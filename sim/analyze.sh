#!/bin/sh
# Analyse all VHDL sources with NVC (syntax + semantic check)
cd "$(dirname "$0")/.."
mkdir -p sim/build && cd sim/build
rm -rf work
nvc --std=1993 --work=work -a --relaxed $(sed 's|^|../../|' ../vhdl_files.txt) "$@"
