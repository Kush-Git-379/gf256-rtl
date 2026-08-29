#!/usr/bin/env bash
# Regenerate golden vectors from the ISRO C++ and run the exhaustive
# testbenches. Exits nonzero if anything fails, so it can gate a commit.
set -euo pipefail

cd "$(dirname "$0")/tb"

echo "[1/3] building + running golden vector generator..."
g++ -O2 -Wall -o gen_golden.exe gen_golden.cpp
mkdir -p golden
./gen_golden.exe

echo
echo "[2/3] compiling RTL + testbenches..."
rm -rf work
vlib work
vlog -sv ../rtl/gf_mul_lut.v ../rtl/gf_mul_shift.v ../rtl/gf_inv.v ../rtl/gf_mac.v tb_gf_mul.sv tb_gf_inv.sv tb_gf_mac.sv | tail -2

echo
echo "[3/3] running exhaustive simulations..."
fail=0
for tb in tb_gf_mul tb_gf_inv tb_gf_mac; do
    out=$(vsim -c -do "run -all; quit -f" "$tb" 2>&1)
    echo "$out" | grep -E "RESULT|MISMATCH|FATAL" || true
    echo "$out" | grep -q "RESULT: PASS" || fail=1
done

echo
if [ "$fail" -ne 0 ]; then
    echo "OVERALL: FAIL"
    exit 1
fi
echo "OVERALL: PASS"
