# Yol Haritası

## anv32i1 Kapanış Notu

Tarih: 2026-06-21

anv32i1 hedefi basit, anlaşılır ve Gowin FPGA üzerinde 27 MHz üstünde kalan bir RV32I MCU core olması. CSR, exception ve tek external interrupt desteği eklendikten sonra timing 27 MHz sınırına çok yaklaştı. Son ölçüm yaklaşık 27.069 MHz; bu yüzden anv32i1'e büyük özellik eklemek yerine minimum doğruluk ve test işleriyle kapatmak daha doğru.

anv32i1 tarafında ileride eklenebilecek küçük işler:

- Misaligned load/store exception.
- Instruction address misaligned exception.
- CSR erişim doğruluğu: unsupported CSR access için illegal instruction, yazılabilir bit maskeleri, WARL davranışlarını sade de olsa toparlama.
- Trap ve interrupt için simülasyon testleri: `ECALL`, illegal instruction, external IRQ, `MRET`.
- GPIO interrupt pending/clear modelini dokümante etmek.

anv32i1'e eklememeyi tercih edeceğimiz daha büyük işler:

- Multiply/divide veya daha geniş execute logic.
- Vectored interrupt veya çok kaynaklı interrupt controller.
- Nested interrupt desteği.
- Gerçek debug module / breakpoint altyapısı.
- Hızlandırıcı arayüzleri.

Bu işler gerekirse `anv32i2` veya ayrı bir debug/peripheral çalışmasının konusu olsun. anv32i1 için ana kural: anlaşılır kal, timing'i 27 MHz altında bırakma.
