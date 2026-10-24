# Benchmarks

The synthetic benchmark suite compares cores by completed work, cycle count,
branch behavior, and optional Fmax-normalized time.

## Run

```sh
make bench
```

Select cores or benchmarks:

```sh
make bench BENCH_CORES=anv32im2 BENCHMARKS=balanced
make bench BENCHMARKS=branch
```

Add Fmax data in MHz:

```sh
make bench BENCH_FMAX='anv32i1=27,anv32im1=27,anv32im2=33'
```

or pass a JSON file:

```json
{
  "anv32i1": 27.0,
  "anv32im1": 27.0,
  "anv32im2": 33.0
}
```

```sh
make bench BENCH_FMAX_JSON=build/fmax.json
```

The runner writes:

- `build/bench/results.json`
- `build/bench/results.csv`

## Counters

- `cycles`: cycles from reset release to benchmark `EBREAK`
- `commits`: non-halt instructions observed at the commit point
- `CPI`: `cycles / commits`
- `branches`: resolved conditional branch instructions
- `taken` / `nt`: actual taken and not-taken conditional branches
- `misp_nt`: conditional branch misses for a static not-taken predictor
- `time_us`: `cycles / fmax_mhz`, only when Fmax is provided
- `MIPS`: `commits * fmax_mhz / cycles`, only when Fmax is provided
- `raw_stall`: cycles where the front-end/decode side stalled for a data hazard
- `load_use`: cycles where that data hazard involved a load result
- `br_redir`: cycles where the core asserted a branch/jump redirect
- `md_stall`: cycles spent waiting for the multi-cycle multiply/divide unit
- `mem_wait`: cycles spent waiting for data memory ready/valid handshaking

`static_nt_mispredicts` in the JSON/CSV includes unconditional jumps as
redirects too. The table's `misp_nt` column is conditional branches only.

`time_us` is total benchmark runtime in microseconds at the given Fmax. Since
1 MHz is 1 cycle per microsecond, `time_us = cycles / fmax_mhz`.

`MIPS` means million instructions per second. The runner uses committed
instructions, so `MIPS = commits / time_us = commits * fmax_mhz / cycles`.

## Benchmark Programs

Assembly microbenchmarks live under `sw/benchmarks`; C kernel benchmarks live
under `sw/benchmarks_c`. Both are described by
`sw/benchmarks/benchmarks.json`. Each program self-checks and writes:

- `a0 = 1` on pass
- `a0 = 0` on fail

The testbench checks `a0` after the final `EBREAK`. Assembly entries use
`"type": "asm"` and C entries use `"type": "c"`. Add a new program, then add
an entry to `benchmarks.json` with `name`, `type`, `src`, `march`,
`max_cycles`, `expected_x10`, and optional `requires`/`tags`.

C benchmarks can use `march_by_core` when the same source should be compiled
differently per core. For example, `anv32i1` can use `rv32i_zicsr` while
`anv32im1` and `anv32im2` use `rv32im_zicsr`, letting compiler-generated
multiply/divide instructions exercise the M extension.
