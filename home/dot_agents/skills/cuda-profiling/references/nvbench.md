# Measure CUDA changes with NVBench

Use the project's existing NVBench targets for CUDA performance benchmarks. Read its build configuration and nearby benchmarks before adding a new target. In a CCCL checkout, read the checkout's `docs/cub/benchmarking.rst`; its guidance also applies to Thrust and libcu++ benchmarks.

## Define a matched comparison

Record the source revisions or patch identities, compiler flags, CCCL/NVBench versions, driver, GPU identity, architecture, and launch configuration. Match input shapes, types, distributions, seeds, axes, allocation policy, and cache/warmup conditions.

Select a GPU explicitly. NVBench's `-d` ordinal is relative to the process's visible devices, so record `CUDA_VISIBLE_DEVICES` and the physical GPU identity. Do not inherit a sample's hard-coded GPU 0 when another device was requested.

Keep other GPU work from contaminating the measurement. Use an existing compute allocation on a shared cluster. Do not change clocks, power limits, permissions, or allocations without authorization.

Define what is timed. A kernel-only benchmark normally prepares data and reusable scratch outside the timed region. An end-to-end benchmark includes allocation, transfers, initialization, or output only when those costs are part of its stated contract. Report the scope rather than comparing unlike measurements.

Check correctness separately. Handle warmup/JIT outside steady-state timing unless startup is the measurement goal. Reset in-place inputs between trials when mutation would change later workloads, and account for the reset outside the intended region.

## Time the work on the benchmark stream

Use the stream supplied by `nvbench::launch` for all timed GPU work. Make the benchmark's allocation/resource device consistent with that stream.

Use the installed NVBench documentation to choose `state.exec` tags:

- The default asynchronous path lets NVBench delimit and synchronize work on its stream.
- `exec_tag::sync` declares that the benchmark body performs the required synchronization itself. Verify that the body or a documented blocking algorithm actually does so. Otherwise the timing can exclude queued work.
- `no_batch` changes the batching strategy; it does not itself make an asynchronous operation synchronous.
- For manual timer tags, verify both timer boundaries and completion according to the installed API.

Avoid accidental synchronization through host-returning Thrust algorithms when measuring asynchronous execution. Reuse scratch/resources outside the timed region when measuring steady-state algorithms. If allocation is intentionally timed, label that result separately.

## Save machine-readable and readable results

Inspect `--help`, benchmark names, and axis names first. Use the same filters for baseline and candidate. This shell template requires paths to already built binaries and a chosen visible device ordinal:

```bash
: "${BASELINE:?Set BASELINE to the baseline benchmark executable}"
: "${CANDIDATE:?Set CANDIDATE to the candidate benchmark executable}"
: "${DEVICE:?Set DEVICE to the chosen visible GPU ordinal}"
: "${OUT:?Set OUT to a new results directory}"
mkdir -- "$OUT"
"$BASELINE" -d "$DEVICE" --stopping-criterion entropy \
	--md "$OUT/baseline.md" --json "$OUT/baseline.json"
"$CANDIDATE" -d "$DEVICE" --stopping-criterion entropy \
	--md "$OUT/candidate.md" --json "$OUT/candidate.json"
```

CCCL recommends the entropy stopping criterion. Check that the pinned NVBench supports it. Keep both JSON and Markdown, exact commands, and exit statuses. Restrict expensive runs with supported `-b` benchmark and `-a` axis filters rather than running every benchmark.

## Compare matched rows and retain uncertainty

Locate the comparison scripts in the project's resolved NVBench source. Do not assume a particular CMake `_deps` path. Use a Python environment with the scripts' declared dependencies already available; do not install packages silently.

```bash
: "${NVBENCH_SCRIPTS:?Set NVBENCH_SCRIPTS to the NVBench python/scripts directory}"
PYTHONPATH="$NVBENCH_SCRIPTS${PYTHONPATH:+:$PYTHONPATH}" \
	python "$NVBENCH_SCRIPTS/nvbench_compare.py" \
	"$OUT/baseline.json" "$OUT/candidate.json"
```

If present in the pinned version, `nvbench_compare_robust.py` provides an interval-based alternative using the same result files. Read its help before choosing filters or interpreting statuses. An ambiguous interval comparison is not proof of a win or parity.

Match benchmark identity and all workload axes. Identify missing/failed/skipped rows rather than dropping them from the conclusion. Report absolute GPU or CPU time, relative change, and measurement noise. Do not combine CPU latency with GPU time or average incompatible shapes into a headline improvement.

When noise prevents a decision, resolve the identified source or use a bounded matched repeat. Do not repeat selectively until the desired result appears. Retain raw results even when no significant change is found.

## Profile separately from timing

Build release code with line information, not `-G`. Use NVBench's `--profile` mode when supported to avoid collecting full profiler reports across timing iterations. Select the kernel and workload, then profile on the same explicit device:

```bash
ncu --kernel-name 'regex:chosen_kernel' --set basic \
	-o "$OUT/kernel" "$CANDIDATE" -d "$DEVICE" --profile
```

Use a new output path. Add only needed counters or sections after the first inspection. Profiler replay and instrumentation alter execution; use the unprofiled NVBench results for latency claims.

Completion criterion: correctness passed, baseline/candidate rows and timing scope match, raw results are retained, and the conclusion accounts for noise and untested cases.

## NVIDIA sources

This is original guidance based on NVIDIA's [CCCL benchmark skill](https://github.com/NVIDIA/cccl/blob/8d33eb1d2cb113bb41ef8733f10baeddb44b7a2c/.agent/skills/cccl-benchmarking/SKILL.md) and [benchmarking guide](https://github.com/NVIDIA/cccl/blob/main/docs/cub/benchmarking.rst). Commands are adapted for explicit user-selected devices and project-resolved paths.

Consult the pinned NVBench versions of [CLI help](https://github.com/NVIDIA/nvbench/blob/main/docs/cli_help.md), [axis filters](https://github.com/NVIDIA/nvbench/blob/main/docs/cli_help_axis.md), and [comparison scripts](https://github.com/NVIDIA/nvbench/tree/main/python/scripts).
