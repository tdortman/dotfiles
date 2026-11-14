---
name: cuda-sass-analysis
description: "Use when inspecting CUDA SASS or PTX to explain a measured bottleneck, choose an optimization, check compiler lowering, or compare generated code across changes. Covers cuobjdump, nvdisasm, registers, spills, memory instructions, dependency chains, and source correlation."
---

# Use SASS to test an optimization hypothesis

Inspect the machine code that executes, connect it to a profiled bottleneck, and test one explanation. SASS is evidence about compiler lowering, not a timing model or proof that one implementation is faster.

Use `cuda-profiling` for workload selection, Nsight measurements, and matched NVBench comparisons. Read `gpu-memory-model` when reasoning about coalescing, bank conflicts, warp participation, or occupancy.

## 1. Identify the executing kernel

Record the hot kernel's full specialization, launch dimensions, dynamic shared memory, input shape/type, target GPU/SM, and contribution to the measured application phase. Distinguish repeated launches of the same symbol.

Find its actual executable, shared library, or generated cubin. Reuse release compiler options from the build system or `compile_commands.json`. Keep optimization, architecture, fast-math, LTO, relocatable-code, and dependency settings identical for a comparison. Use line information where available, not `-G`.

Record compiler, binary-tools, driver, and dependency versions. A standalone reproduction can explain a lowering, but is not proof of the application's final linked code.

Check whether the runtime uses a native cubin or JIT-compiles embedded PTX. Dumping an unrelated embedded SM image does not describe the executed kernel. If only PTX is available, label the result as PTX analysis until the actual generated machine code is captured.

For unfamiliar opcodes or tool options, query `nvidia-cuda-docs/search_cuda_docs` first with the exact SM and toolkit. In omp, read `xd://mcp__nvidia_cuda_docs_search_cuda_docs` for the schema, then write `{"query":"..."}` to it. Confirm options with the installed tool's help and NVIDIA's Binary Utilities reference when search results are incomplete.

Completion criterion: the source configuration, final binary, kernel specialization, and target image under inspection are identified.

## 2. Keep raw disassembly and resource evidence

Use `cuobjdump` for a host executable, library, or cubin. The following shell template requires an existing `BINARY` and a new output directory:

```bash
: "${BINARY:?Set BINARY to the release executable or library}"
: "${OUT:?Set OUT to a new analysis directory}"
mkdir -- "$OUT"
cuobjdump --list-elf "$BINARY" > "$OUT/images.txt"
cuobjdump --dump-resource-usage "$BINARY" > "$OUT/resources.txt"
cuobjdump --dump-sass "$BINARY" > "$OUT/raw.sass"
```

Select the architecture and kernel from these outputs. Preserve the raw files. For a selected native cubin, `nvdisasm` provides source-line annotations:

```bash
: "${CUBIN:?Set CUBIN to the selected native cubin}"
nvdisasm --print-line-info "$CUBIN" > "$OUT/lines.sass"
```

To extract embedded cubins, inspect `cuobjdump --list-elf` and use `--extract-elf` with the chosen image name in a dedicated directory. Extraction writes files into the working directory. Resolve the binary path before changing directories. `nvdisasm` expects a cubin, not a host executable. An older binary tool may not understand a newer cubin.

For controlled recompilation, retain `ptxas` resource diagnostics with `-Xptxas=-v`. Inspect register allocation, static/dynamic shared memory, stack frames, and reported spill loads/stores. Keep those measurements per kernel and per SM rather than treating one aggregate as universal.

Completion criterion: raw machine code and matching resource usage are available for the selected kernel.

## 3. Read the hot path, not every instruction

Start at the source region implicated by profiling. Line mappings can include inlined functions and reordered instructions; inspect the surrounding control flow and operand definitions.

Use these questions to form a specific hypothesis:

| Evidence to inspect | Question and required corroboration |
|---|---|
| Global load/store width, address arithmetic, predicates, and cache modifiers | Did vectorization or address calculation change? Check alignment and runtime addresses; a wide load does not prove coalescing. |
| Local-memory instructions and stack accesses | Are these spills, address-taken arrays, call frames, or another local allocation? Use `ptxas` diagnostics and NCU local-memory traffic before calling them spills. |
| Registers, live values, and independent operations | Is a longer live range reducing residency or is a dependency chain limiting issue rate? Check occupancy limits and scheduler/stall evidence. |
| Branches, predication, loops, and unrolling | Which paths and iterations actually execute? Check dynamic counts and divergence; a longer static listing can execute less work. |
| Barriers, waits, fences, atomics, and async-copy instructions | Is synchronization or serialization on the critical path? Check participating threads and timeline/counter evidence. Do not remove ordering to improve a listing. |
| Integer divides, conversions, repeated address work, and specialized instructions | Did the compiler miss known bounds or type information? Test whether a valid source-level change improves lowering without altering semantics. |

Trace producer/consumer operands through a short region. Count dependencies and memory operations relevant to the hypothesis, not all text lines. Treat latency and throughput as architecture-specific. Do not infer dynamic instruction count from a static opcode count.

Correlate NCU samples and counters with the same kernel and launch configuration. A sampled stall site is not automatically the instruction that caused the stall. High register allocation is not automatically a spill, low occupancy is not automatically a bottleneck, and fewer instructions are not automatically faster.

## 4. Compare without deleting semantic differences

Build baseline and candidate with matched settings and inspect the same specialization and SM. Use separate outputs or an authorized isolated checkout; preserve unrelated work.

Ignore cosmetic address, label, and symbol changes only after matching functions and control-flow regions. Register renaming can be cosmetic, but changed data dependencies, allocated register count, predicates, instruction scheduling/control metadata, cache modifiers, memory widths, or branch targets are evidence to retain.

Do not strip operands or all immediates with a broad regular expression to manufacture a clean diff. Basic-block reordering requires checking control-flow equivalence. Preserve resource deltas even when the opcode sequence looks identical.

For generic kernels or architecture dispatch changes, inspect the affected types and SM images, including non-default specializations. State the tested subset. One clean specialization does not establish code-generation parity for a public template.

## 5. Test one explanation

Write a falsifiable claim before changing code, for example: "This temporary extends live ranges across the loop; shortening its lifetime should reduce allocated registers without increasing spill traffic."

Make the smallest source-level change that tests the claim. Preserve aliasing, alignment, numerical, and synchronization contracts. Do not add `restrict`, approximate math, forced register caps, or inline PTX merely because they might improve assembly.

Run the affected correctness check and a matched, unprofiled benchmark. Reinspect code generation and the counters needed for the hypothesis. Use `cuda-profiling` for warmup, timing scope, noise, and result retention. Profiling replay time is not application latency.

If SASS improves but timing does not, report that distinction. The code change may not address the real bottleneck. Keep or discard it according to the user's goal, without overwriting unrelated work.

## Report evidence separately from inference

Report the kernel, SM/toolchain, workload, and paths to raw artifacts. Show only the few source/SASS regions that support the decision.

Separate:

- Observed instruction and resource differences.
- Inferred mechanism and supporting profiler evidence.
- Correctness result and measured benchmark delta with noise.
- Decision and untested configurations.

Completion criterion: the recommendation follows from observed code generation and the requested measurement, or is explicitly limited to an untested hypothesis.

## Sources

The comparison workflow draws on NVIDIA CCCL's [sass-diff skill](https://github.com/NVIDIA/cccl/blob/8d33eb1d2cb113bb41ef8733f10baeddb44b7a2c/.agent/skills/sass-diff/SKILL.md). This is a separately written analysis workflow, not a verbatim copy. Consult the source repository's [license notices](https://github.com/NVIDIA/cccl/blob/main/LICENSE) before copying its text or assets.

Use NVIDIA's [CUDA Binary Utilities](https://docs.nvidia.com/cuda/cuda-binary-utilities/index.html), [Nsight Compute Profiling Guide](https://docs.nvidia.com/nsight-compute/ProfilingGuide/index.html), and [PTX ISA](https://docs.nvidia.com/cuda/parallel-thread-execution/index.html). PTX describes a virtual ISA, not the final SASS instruction stream.
