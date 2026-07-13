#!/usr/bin/env python3
# make-edid.py — generate a valid 1920x1200@60 (CVT-RB) EDID blob.
# Used to force a spare DRM connector on as a virtual monitor (see docs/second-monitor-kde.md).
# Usage: python3 make-edid.py [out.edid]   (default: vm.edid)
import sys
out = sys.argv[1] if len(sys.argv) > 1 else "vm.edid"
e = bytearray(128)
e[0:8] = bytes([0, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0])
e[8] = 0x31; e[9] = 0xD8            # mfg id "LNX"
e[10] = 0x01; e[11] = 0x00          # product
e[12:16] = bytes([1, 0, 0, 0])      # serial
e[16] = 1; e[17] = 30               # week 1, year 2020
e[18] = 1; e[19] = 3                # EDID 1.3
e[20] = 0x80                        # digital input
e[21] = 52; e[22] = 32              # image size cm
e[23] = 120                         # gamma 2.2
e[24] = 0x02                        # preferred timing
e[25:35] = bytes([0xEE, 0x91, 0xA3, 0x54, 0x4C, 0x99, 0x26, 0x0F, 0x50, 0x54])
for i in range(38, 54):
    e[i] = 0x01
# DTD 1: 1920x1200@60 CVT-RB, pixel clock 154.00 MHz
p = 15400
e[54] = p & 0xFF; e[55] = (p >> 8) & 0xFF
ha, hb = 1920, 160
e[56] = ha & 0xFF; e[57] = hb & 0xFF; e[58] = ((ha >> 8) << 4) | ((hb >> 8) & 0xF)
va, vb = 1200, 35
e[59] = va & 0xFF; e[60] = vb & 0xFF; e[61] = ((va >> 8) << 4) | ((vb >> 8) & 0xF)
hf, hs = 48, 32
e[62] = hf & 0xFF; e[63] = hs & 0xFF
vf, vs = 3, 6
e[64] = ((vf & 0xF) << 4) | (vs & 0xF)
e[65] = (((hf >> 8) & 3) << 6) | (((hs >> 8) & 3) << 4) | (((vf >> 4) & 3) << 2) | ((vs >> 4) & 3)
hmm, vmm = 518, 324
e[66] = hmm & 0xFF; e[67] = vmm & 0xFF; e[68] = ((hmm >> 8) << 4) | ((vmm >> 8) & 0xF)
e[69] = 0; e[70] = 0; e[71] = 0x1A  # hsync+, vsync-, digital separate
# DTD 2: monitor name
e[72] = 0; e[73] = 0; e[74] = 0; e[75] = 0xFC; e[76] = 0
e[77:90] = (b"medion-vm\x0a" + b" " * 13)[:13]
# DTD 3: range limits 50-75Hz, 30-95kHz, pclk 160MHz
e[90] = 0; e[91] = 0; e[92] = 0; e[93] = 0xFD; e[94] = 0
e[95] = 50; e[96] = 75; e[97] = 30; e[98] = 95; e[99] = 16; e[100] = 0x0A
e[101:108] = b" " * 7
# DTD 4: dummy
e[108] = 0; e[109] = 0; e[110] = 0; e[111] = 0x10; e[112] = 0
e[126] = 0
e[127] = (256 - (sum(e[0:127]) % 256)) % 256
open(out, "wb").write(bytes(e))
print(f"wrote {out} (1920x1200@60, checksum 0x{e[127]:02X})")
