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

## I2C Peripheral Notları

Tarih: 2026-06-28

I2C çekirdeği şu an temel master transmit tarafını çalıştırıyor. Tang Nano 9K üzerinde 2x16 I2C LCD backpack ile ACK alındı ve `ANV32 I2C OK` yazısı başarıyla gösterildi. Bu aşama I2C bit sürme, open-drain kullanım, START/STOP, ACK okuma ve basit write transaction için iyi bir doğrulama oldu.

Mevcut durumda olanlar:

- `i2c_byte_master`: START, byte transmit, ACK okuma ve STOP üretiyor.
- `i2c_master_write`: address + data write transaction yapıyor.
- LCD ACK/text FPGA test top'ları var.
- Temel transmit arbitration-lost algılama eklendi: master SDA'yı release edip `1` göndermek isterken hatta `0` okursa işlem kesiliyor.

Profesyonel MCU seviyesine yaklaşmak için kalan işler:

- Clock stretching desteği: SCL release edildikten sonra gerçekten high olana kadar beklemek.
- RX byte desteği: master read sırasında SDA okuma, son byte için NACK üretme.
- Repeated START desteği: register read akışları için `START + addr W + reg + repeated START + addr R`.
- Timeout altyapısı: clock stretching veya stuck bus durumunda sonsuz beklememek.
- Bus busy algılama: işlem başlatmadan önce SDA/SCL durumunu kontrol etmek.
- Stuck bus recovery: SDA low kalırsa SCL'ye 9 pulse gönderip STOP denemek.
- Transaction controller: byte engine üstünde multi-byte write/read/register-read/register-write akışları.
- FIFO veya command queue: CPU'nun her byte için beklememesi için TX/RX FIFO ya da komut kuyruğu.
- MMIO wrapper: `CTRL`, `STATUS`, `BAUD_DIV`, `TXDATA`, `RXDATA`, `IRQ_STAT`, `IRQ_EN`, `TIMEOUT` gibi register map.
- Interrupt desteği: done, RX ready, TX empty, NACK, arbitration lost, timeout ve bus error için IRQ.
- Hata/status temizleme modeli: write-1-to-clear status bitleri.
- Test kapsamı: byte engine waveform testleri, NACK, arbitration lost, clock stretching, repeated START ve LCD/sensör smoke testleri.

Önerilen sıradaki teknik adım: önce clock stretching'i ekle. Bunun için SCL'yi bıraktıktan sonra `scl_io` gerçekten `1` olana kadar high faza geçme. Bu değişiklik I2C engine'i gerçek cihazlarla daha uyumlu hale getirir ve timeout tasarımının da temelini oluşturur.
