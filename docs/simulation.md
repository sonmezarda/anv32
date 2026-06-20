# Simulasyon ve Yazilim Test Akisi

Bu not, Verilator testlerini ve C programindan BRAM image'i uretme akisinin
kisa kullanim kilavuzudur.

## Gerekenler

- `verilator`
- `python3`
- RISC-V bare-metal toolchain:
  - `riscv64-unknown-elf-gcc`
  - `riscv64-unknown-elf-objcopy`
  - `riscv64-unknown-elf-objdump`

Varsayilan toolchain `riscv64-unknown-elf-*` isimlerini kullanir. Farkli isimli
bir toolchain varsa Makefile degiskenleriyle verilebilir.

## RTL Testleri

Varsayilan hedef decode/execute stage testidir:

```sh
make
```

Ayni test acik hedefle de calistirilabilir:

```sh
make de
```

Fetch top testi:

```sh
make fetch_top
```

Memory stage testi:

```sh
make m
```

Kayitli tum testleri calistirmak:

```sh
make all
```

Test ismini degiskenle secmek:

```sh
make test TEST=de
make test TEST=m
make test TEST=fetch_top
```

Kayitli testleri listelemek:

```sh
make list
```

Verilator lint uyarilarini bastirmadan gormek:

```sh
make WARN=1 de
make WARN=1 m
make WARN=1 fetch_top
```

Ek Verilator flag'i vermek:

```sh
make de EXTRA_VFLAGS="--trace"
```

## Word Hex'i Byte-Lane Hex'e Bolmek

BRAM byte-lane split oldugu icin 32-bit word hex dosyasi dort tane byte-lane
hex dosyasina cevrilir.

Varsayilan kaynak:

```text
sim/hex/prog.hex
```

Varsayilan komut:

```sh
make hex
```

Bu komut sunlari uretir:

```text
sim/hex/prog_lane0.hex
sim/hex/prog_lane1.hex
sim/hex/prog_lane2.hex
sim/hex/prog_lane3.hex
```

Baska program adi icin:

```sh
make hex PROG=blink
```

Bu durumda kaynak `sim/hex/blink.hex`, ciktilar da
`sim/hex/blink_lane0.hex` ... `sim/hex/blink_lane3.hex` olur.

## C Programindan Simulasyon Image'i

Varsayilan C ornegi:

```text
sw/examples/smoke.c
```

Programi build edip uretilen image'in fetch yolu uzerinden okunabildigini
dogrulamak:

```sh
make sw-fetch
```

Bu akis su ara adimlari yapar:

1. C source -> assembly `.s`
2. assembly -> object `.o`
3. `crt0.S` + object -> ELF
4. ELF -> raw binary `.bin`
5. binary -> 32-bit word hex `.hex`
6. word hex -> 4 byte-lane hex
7. Verilator ile `tb_program_fetch` calistirma

`KEEP` verilmezse tum ara dosyalar gecici dizinde uretilir ve test bitince
otomatik silinir.

## Ara Dosyalari Saklamak

Assembly, word hex ve lane hex dosyalarini gormek:

```sh
make sw-fetch KEEP=asm,hex,lanes
```

Varsayilan cikti dizini:

```text
build/sw/smoke/
```

Ornek ciktilar:

```text
build/sw/smoke/smoke.s
build/sw/smoke/smoke.hex
build/sw/smoke/smoke_lane0.hex
build/sw/smoke/smoke_lane1.hex
build/sw/smoke/smoke_lane2.hex
build/sw/smoke/smoke_lane3.hex
```

Daha fazla ara dosya saklamak:

```sh
make sw-fetch KEEP=all
make sw-fetch KEEP=asm,hex,lanes,elf,dump,map
```

Desteklenen `KEEP` isimleri:

```text
asm
hex
lanes
elf
bin
dump
map
obj
all
```

## Kendi C Programini Calistirmak

Tek dosyali bir C programi yaz:

```c
int main(void)
{
    volatile int a = 10;
    volatile int b = 20;
    return a + b;
}
```

Ornek dosya yolu:

```text
sw/examples/add_test.c
```

Calistirma:

```sh
make sw-fetch C_SRC=sw/examples/add_test.c SW_NAME=add_test
```

Ara dosyalari da saklayarak:

```sh
make sw-fetch C_SRC=sw/examples/add_test.c SW_NAME=add_test KEEP=asm,hex,lanes,dump
```

Bu durumda ciktilar:

```text
build/sw/add_test/add_test.s
build/sw/add_test/add_test.hex
build/sw/add_test/add_test_lane0.hex
build/sw/add_test/add_test_lane1.hex
build/sw/add_test/add_test_lane2.hex
build/sw/add_test/add_test_lane3.hex
build/sw/add_test/add_test.dump
```

`SW_NAME` verilmezse dosya adindan turetilir.

## Spike Golden Diff Test

Assembly programini 0x80000000 adresine linkleyip hem Spike hem de core
uzerinde calistirmak ve commit loglarini karsilastirmak:

```sh
make asm-diff-test ASM=sw/examples/hazard_raw.S
```

Bu akis su dosyalari uretir:

```text
build/golden/asm/hazard_raw/spike.raw.log
build/golden/asm/hazard_raw/spike.norm.log
build/golden/asm/hazard_raw/core.norm.log
build/golden/asm/hazard_raw/pipeline.log
build/golden/asm/hazard_raw/commit.diff
```

`spike.norm.log` ve `core.norm.log` PC, instruction word ve register write
event'leri uzerinden karsilastirilir. Spike'in mnemonic/alias yazimi diff'e
dahil edilmez.

Ornek JALR/flush testi:

```sh
make asm-diff-test ASM=sw/examples/hazard_auipc_jalr.S CYCLES=30 SPIKE_INSNS=30
```

Sadece golden + pipeline loglarini uretmek, diff calistirmamak icin:

```sh
make asm-golden-run ASM=sw/examples/hazard_raw.S CORE_NORM_LOG=build/golden/asm/hazard_raw/core.norm.log
```

## Toolchain Ismini Degistirmek

Toolchain isimleri sistemde farkliysa:

```sh
make sw-fetch \
  SW_CC=riscv32-unknown-elf-gcc \
  SW_OBJCOPY=riscv32-unknown-elf-objcopy \
  SW_OBJDUMP=riscv32-unknown-elf-objdump
```

## Temizlik

Verilator ciktilarini, uretilen lane hex dosyalarini ve `build/sw` altindaki
saklanan yazilim artefact'larini temizlemek:

```sh
make clean
```

## Su Anki Kapsam

`sw-fetch` hedefi su an C programindan uretilen instruction image'inin BRAM
byte-lane init dosyalariyla dogru okunabildigini fetch yolu uzerinden dogrular.
Yani bu hedef programin tum instruction word'lerini fetch eder ve beklenen
word hex ile karsilastirir.

Tam core topolojisi fetch + DE + MW + regfile olarak baglandiginda ayni C build
hatti dogrudan "programi calistir, sonucu kontrol et" testbench'ine baglanabilir.
`crt0.S`, `main()` donus degerini `_test_result` sembolune yazar ve sonra
`ebreak` uretir; bu da ileride full-core simulasyonunda bitis/success noktasi
olarak kullanilabilir.
