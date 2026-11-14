---
name: cccl-algorithms
description: "Use before writing CUDA kernels for reductions, scans, sorting, top-k, histograms, compaction, search, or transforms. Also use when reviewing, optimizing, debugging, or migrating Thrust, CUB, and libcu++ algorithms, including execution environments, accumulator types, and determinism."
license: CC-BY-4.0
---

# Choose and compose CCCL algorithms

Check NVIDIA CCCL before writing a custom CUDA kernel. Use a library algorithm when it meets the required semantics and measured performance. Compose iterators and operations before materializing intermediate arrays. A custom kernel needs a concrete reason, such as an unsupported operation, fusion requirement, or measured bottleneck.

This skill covers algorithm selection and contracts. Use `nvidia-cccl-runtime` for explicit device selection, streams, buffers, and lifetime management. Use `cuda-profiling` for benchmarking and performance evidence.

## Establish the installed contract

1. Identify the resolved CCCL headers, compiler, C++ standard, and supported deployment versions. A separately supplied CCCL can differ from the toolkit's bundled version.
2. Query `nvidia-cuda-docs/search_cuda_docs` first. Include the algorithm, intended semantics, and target version. In omp, read `xd://mcp__nvidia_cuda_docs_search_cuda_docs`, then write `{"query":"..."}` to that device.
3. Check the selected overload in release-matched documentation and installed headers. If MCP is unavailable or incomplete, use the NVIDIA sources below. State unresolved gaps.

Do not assume a CUDA major version identifies the exact CCCL release. Check the project's actual compiler include configuration. To inspect `CCCL_VERSION`, use that configuration with:

```bash
printf '#include <cuda/version>\nCCCL_VERSION\n' | nvcc -x cu -E -
```

For CUDA 13 installations, check whether host C++ compilation receives the toolkit's `include/cccl` directory. Use the project's imported dependency targets or package configuration to propagate includes. Keep includes such as `<thrust/host_vector.h>`, not `<cccl/thrust/host_vector.h>`. Avoid hard-coded toolkit paths.

Completion criterion: the chosen API, overload, and required properties exist in every supported configuration affected by the change.

## Select an algorithm family

Use this map to narrow the lookup, not as a promise that every symbol exists in older releases:

| Required operation | Candidates |
|---|---|
| Sum or custom aggregate | `thrust::reduce`, `thrust::transform_reduce`, `cub::DeviceReduce` |
| Minimum or maximum with position | `thrust::min_element`, `thrust::max_element`, CUB ArgMin or ArgMax |
| Prefix sums | Thrust scans, `cub::DeviceScan` |
| Full sort or key/value sort | Thrust sort algorithms, `cub::DeviceRadixSort` |
| Top-k only | `cub::DeviceTopK`, or selection followed by sorting only the selected results |
| Segmented operations | `cub::DeviceSegmentedReduce`, `DeviceSegmentedScan`, `DeviceSegmentedSort` |
| Consecutive-key aggregation | `thrust::reduce_by_key`, CUB ReduceByKey |
| Histogram | `cub::DeviceHistogram` |
| Filter, compact, or partition | Thrust copy/remove/partition algorithms, `cub::DeviceSelect`, `DevicePartition` |
| Run lengths or distinct count in sorted input | `cub::DeviceRunLengthEncode`, `thrust::unique_count` where available |
| Search, first mismatch, or merge | Thrust find, mismatch, lower_bound, and merge algorithms |
| Elementwise work | `thrust::transform`, `for_each`, `cub::DeviceTransform`, `DeviceFor` |
| Device-callable building blocks | CUB block/warp collectives and libcu++ device utilities |

For modern standard-style GPU algorithms, check `cuda::std` algorithm support and the `cuda::execution::gpu` policy in the installed release. Attach the intended stream explicitly. Host `std::execution::par` does not by itself select a CUDA backend.

## Check semantics before choosing the fastest path

- Trace input, accumulator, initial-value, output, and index types separately. A wider output does not necessarily widen accumulation. Thrust reduction initialization with `0` can select integer accumulation for floating-point input. CUB deduction differs by overload and operator; inspect it rather than generalizing Thrust's rule.
- Widen operands before size or byte-offset arithmetic. Carry a supported wide item-count/index type through iterators and the full algorithm, not just its public parameter.
- Verify identity, empty input, NaN/infinity behavior, ties, and stable-order requirements. Test first-position ties when callers require them. Check whether a minimum API uses a finite identity when the application needs positive infinity.
- Check associativity and permitted operand reordering. Device-wide CUB Reduce does not support noncommutative operators. Ordered composition may need an order-preserving scan followed by its final result. Do not extend one algorithm's restriction to every reduction or collective.
- `reduce_by_key` and unique operations act on consecutive equal values. Sort or otherwise group keys when global grouping is required.
- For `HistogramEven`, distinguish bin count from level count and check the half-open sample range. A 256-bin byte histogram uses 257 levels spanning `[0, 256)`.
- Read `cub::DoubleBuffer::Current()` after operations that can alternate buffers. Do not assume the originally supplied buffer contains the result.
- Validate radix-sort bit ranges against the documented signed/floating-point key transformation. Restrict bits only when that transformed ordering matches the contract. A custom comparator may select a different sorting algorithm.
- Top-k does not imply sorted output, deterministic ties, or a stable order. Check the installed `DeviceTopK` requirements. Some releases require explicit `determinism::not_guaranteed` and `output_ordering::unsorted` properties. Sort the selected pairs afterward if callers need ordered results.

Completion criterion: each application requirement has an explicit algorithm guarantee or a checked transformation that provides it.

## Compose work without hidden synchronization

Pass the caller's stream to every algorithm. Raw device pointers need an explicit device execution policy when Thrust cannot infer their system. Prefer a stream-bound policy over a global default.

Distinguish host-returning algorithms from device-output algorithms. Thrust calls returning a host scalar or data-dependent iterator can require completion before returning. `thrust::cuda::par.on(stream)` can synchronize; `par_nosync.on(stream)` permits asynchronous execution where supported, but does not make every operation nonblocking.

For overlapping streams, keep results on the device with an available device-output algorithm, such as CUB reduction or `thrust::reduce_into`. Establish cross-stream dependencies explicitly. Synchronize at the caller boundary that needs completed results.

Modern CUB overloads can accept a stream or `cuda::std::execution::env` combining stream, memory resource, and requirements. Verify the overload and construct the environment for the intended device. A default environment is not a substitute for explicit stream selection.

Continue checking CUB's returned `cudaError_t` where the interface returns a status. CCCL's C++ runtime preference does not turn CUB status-returning APIs into exception-based ones. Check asynchronous execution at a completion boundary too.

Reuse scratch allocations across repeated calls. If the supported API uses the two-call temporary-storage protocol, query and allocate outside the hot loop when size and configuration are unchanged. If an environment allocates scratch internally, use an appropriate reusable memory resource and measure that path.

Fuse transforms into consumers using transform, zip, counting, and permutation iterators. Combine related aggregate results into one reduction when the operator and numerical contract permit it. Account for register pressure and repeated computation; fusion is a measured choice, not an unconditional win.

For segmented work, check fixed-size segment overloads when lengths are uniform. For variable lengths, compare suitable segmented and by-key approaches against actual segment distributions. Do not import another workload's segment-size threshold or speedup.

## Request determinism explicitly

Separate same-GPU rerun reproducibility from cross-architecture reproducibility. Floating-point addition is not mathematically associative in machine arithmetic. Changing precision alone does not establish a bitwise guarantee.

Check each algorithm's documented default and supported `cuda::execution::determinism` requirements. Where supported, combine a requirement with the explicit stream in an execution environment. Treat unsupported guarantees as a design constraint, not a reason to silently drop the requirement.

Do not assume floating-point scans or by-key reductions share DeviceReduce's default guarantees. Cross-GPU deterministic modes can be restricted by type and operator. Fixed-point conversion changes numerical semantics and needs range/error analysis plus user agreement when it changes the contract.

Measure the cost of the requested guarantee. Do not promise that determinism is free or transfer a timing from another GPU.

## Preserve device-collective participation

When a library-wide algorithm cannot express the operation, prefer suitable CUB block/warp collectives inside the custom kernel.

Match template dimensions and participating lanes to the launch. Keep barriers and collectives uniform across their required participants, including tail handling. Observe documented result-valid threads and synchronize before reusing shared temporary storage. An early return that skips a later collective can break otherwise valid inputs.

## Migrate and verify through a real caller

For CCCL upgrades, consult the release migration guide. Replace removed APIs with supported equivalents in every affected caller. Do not recreate removed symbols inside NVIDIA namespaces, pin an old release to mask the problem, or add compatibility aliases without a supported-version requirement.

Use a focused consumer check with a CPU/reference result. Select meaningful edges from the changed contract: empty input, a partial block, ties, overflow-prone accumulation, special floating-point values, long key runs, or a non-default stream. Test requested determinism at its declared scope. Keep correctness checks outside timed regions.

For performance changes, follow `cuda-profiling`: report matched unprofiled timings, workload and allocation scope, and measurement noise. Explain why a library composition or custom kernel was selected.

## Sources and attribution

Adapted from NVIDIA's [CCCL consumer skill](https://github.com/NVIDIA/cccl/blob/19eb098240768f1ac25ac3e693cd40432815175e/skills/cccl/SKILL.md), proposed in [PR #12579](https://github.com/NVIDIA/cccl/pull/12579), under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Changes separate runtime guidance, qualify version-sensitive contracts, remove fixed performance claims, and add explicit verification criteria. This adaptation is not an NVIDIA endorsement.

Use release-matched versions of the [CCCL documentation](https://nvidia.github.io/cccl/), including the [CUB algorithm catalog](https://nvidia.github.io/cccl/unstable/cub/device_wide.html), [execution environments](https://nvidia.github.io/cccl/unstable/cub/environment.html), [determinism](https://nvidia.github.io/cccl/unstable/cub/determinism.html), and [3.0 migration guide](https://nvidia.github.io/cccl/unstable/cccl/3.0_migration_guide.html).
