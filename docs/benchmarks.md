# ANV32 benchmark runner

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
make bench BENCH_FMAX='anv32i1=40,anv32im1=35,anv32im2=45'
```

or pass a JSON file:

```json
{
  "anv32i1": 40.0,
  "anv32im1": 35.0,
  "anv32im2": 45.0
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

`static_nt_mispredicts` in the JSON/CSV includes unconditional jumps as
redirects too. The table's `misp_nt` column is conditional branches only.

## Benchmark Programs

Benchmarks live under `sw/benchmarks` and are described by
`sw/benchmarks/benchmarks.json`. Each program self-checks and writes:

- `a0 = 1` on pass
- `a0 = 0` on fail

The testbench checks `a0` after the final `EBREAK`. Add a new assembly program,
then add an entry to `benchmarks.json` with `name`, `src`, `march`,
`max_cycles`, `expected_x10`, and optional `requires`/`tags`.
