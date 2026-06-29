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

Tarih: 2026-06-28, güncelleme: 2026-06-29

I2C çekirdeği önce temel master transmit tarafıyla başladı. Tang Nano 9K üzerinde 2x16 I2C LCD backpack ile ACK alındı ve `ANV32 I2C OK` yazısı başarıyla gösterildi. Sonra timed byte engine, clock stretching bekleme, read byte, repeated START ve QMC5883L manyetometre register read/write akışları eklendi. QMC5883L üzerinden gerçek XYZ verisi okunarak write/read tarafı donanımda doğrulandı.

Mevcut durumda olanlar:

- `i2c_byte_master_timed`: START, repeated START, byte transmit, ACK okuma, byte receive, master ACK/NACK ve STOP üretiyor.
- SCL release edildikten sonra gerçek `scl_i` high olana kadar bekleyerek clock stretching destekliyor.
- Stretch timeout ve transmit arbitration-lost algılama var.
- `i2c_cmd_master_timed`: byte engine üstünde command queue, RX FIFO, bus busy/free check, bus recovery ve sticky error bitleri sağlıyor.
- `i2c_periph`: SoC tarafına `CMD`, `STATUS`, `RXDATA`, `CTRL` register map'iyle bağlanıyor.
- Eski senaryo helper modülleri (`write`, `read`, `reg_read`, LCD/probe test top'ları) ayıklandı; bu akışlar artık yazılımdan command queue'ya komut dizerek yapılacak.
- `sw/fpga/i2c_qmc5883l.c`: command queue tabanlı QMC5883L smoke test programı.

Profesyonel MCU seviyesine yaklaşmak için kalan işler:

- Daha esnek timing register'ları: `SCL_LOW`, `SCL_HIGH`, `STRETCH_TIMEOUT` değerlerini MMIO'dan ayarlanabilir yapmak.
- Error sonrası politika: NACK/arbitration/timeout durumunda command queue'yu otomatik durdurma veya yazılım kontrollü devam etme seçeneği.
- Interrupt modeli: RX ready, command done, command empty, error ve recovery done için ayrı IRQ status/enable bitleri.
- Command queue seviye sayaçları: TX command FIFO level ve RX FIFO level bilgisini status register'a eklemek.
- Bus recovery geliştirme: recovery sonunda SDA/SCL hâlâ serbest değilse daha net stuck-low sebebi raporlamak.
- Test kapsamı: command queue overflow, RX overflow, NACK, arbitration lost, clock stretching, recovery ve repeated START için simülasyon testleri.
- Bus wrapper standardizasyonu: UART/I2C/GPIO/TIMER için ortak peripheral bus protokolüne taşımak.

Önerilen sıradaki teknik adım: I2C register map'i biraz daha MCU benzeri hale getirip timing ve IRQ ayarlarını MMIO'ya taşımak. Ardından ortak peripheral bus tasarımına geçerken bu register modelini UART ile aynı disipline sokmak.
