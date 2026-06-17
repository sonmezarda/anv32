# anv32 — RISC-V MCU

ArniComp (8-bit) deneyiminden sonra: **RV32IM** tabanlı, interrupt destekli,
swappable-core mimarisine sahip bir mikrokontrolcü çekirdeği ve SoC'u.

## Aile / Parça İsimlendirme

| İsim        | Ne                                   |
|-------------|--------------------------------------|
| `anv32`     | Aile / SoC platformu (sabit kimlik)  |
| `anv32i1`   | Çekirdek: RV32I, 3-stage in-order    |
| `anv32im1`  | Çekirdek: RV32IM, 3-stage in-order   |
| `anv32im2`  | Çekirdek: RV32IM, 5-stage (deney)    |

Şema: harfler = ISA (`i` → `im`), son rakam = mikromimari revizyonu.
SoC sabittir; çekirdek takılıp çıkarılabilir (swappable core).

## Çekirdek Kararlar

- ISA: `RV32IM` + `Zicsr` (kademeli: önce I, sonra M)
- Privilege: M-mode (U-mode RTOS'a ertelendi)
- Pipeline: 3-stage in-order (sonra 5-stage varyantı ile karşılaştırma)
- Bellek: **modified Harvard** — ayrı I/D portu, birleşik adres uzayı
- Bellek tipi: senkron BRAM (1-cycle read), regfile async LUTRAM
- Bus: AHB-Lite (core) + APB (peripheral), AHB-to-APB bridge
- Interrupt: CLINT → CLIC (kademeli)
- Golden reference: Spike ile co-simulation

## Dizin Yapısı

- `rtl/`          — tüm RTL (tek kaynak doğruluğu). Gowin bunu *referanslar*.
- `sim/`          — Verilator harness + testbench'ler
- `sw/`           — çekirdekte koşacak yazılım (crt0, linker script, örnekler)
- `tests/`        — riscv-tests / riscv-arch-test uyumluluk testleri
- `fpga/gowin/`   — Gowin projesi (rtl/'i referanslar, kopyalamaz)
- `tools/`        — host scriptleri (UART yükleyici vb.)
- `docs/`         — tasarım notları ve karar kayıtları

## Yol Haritası

Bkz. `docs/roadmap.md` — M0 (kurulum) → M14 (inovasyon).
