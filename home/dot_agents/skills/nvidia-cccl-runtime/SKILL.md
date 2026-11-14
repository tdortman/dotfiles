---
name: nvidia-cccl-runtime
description: "Use when writing or migrating CUDA host code for device selection, streams, events, allocation, copies, or kernel launches. Prefer CCCL Runtime C++ APIs over equivalent CUDA C APIs, with explicit device identity and ownership, especially for multi-GPU code."
---

# Prefer CCCL Runtime for CUDA host code

Use NVIDIA's CCCL Runtime C++ APIs when an equivalent exists in the project's supported CCCL release. Prefer explicit device identity, typed arguments, and RAII over implicit current-device state and manual resource management. A shorter C call is not a reason to bypass an available C++ equivalent.

This is a host-side runtime skill. Keep CUB, Thrust, and other suitable NVIDIA algorithms for computation. Do not replace them with custom kernels to adopt this runtime.

## 1. Establish the supported API

Before editing, identify the resolved CCCL version, CUDA compiler, language standard, and supported deployment toolkits. Inspect dependency pins and actual compiler include paths. A separately supplied CCCL can differ from the toolkit's bundled headers.

Use the `nvidia-cuda-docs` MCP server's `search_cuda_docs` tool as the first documentation lookup. Query the exact API, required behavior, and target CCCL version. For example: "CCCL Runtime cuda::buffer host-source lifetime and stream-ordered deallocation in CCCL 3.2."

In omp, read `xd://mcp__nvidia_cuda_docs_search_cuda_docs` for the schema, then write a JSON object with a `query` string to that same device. If the server is unavailable or its results do not cover the question, consult the NVIDIA sources below and the installed headers. State any unresolved documentation gap.

Check each proposed API against that release's headers and NVIDIA documentation. The linked `unstable` documentation tracks development, not necessarily the installed release. Do not infer availability from an unversioned example or from `nvcc --version` alone.

The documentation checked on 2026-11-14 lists these starting points:

- CCCL 2.2 / CUDA 12.3: `cuda::stream_ref`.
- CCCL 3.1 / CUDA 13.1: `cuda::devices`, `cuda::device_ref`, owning streams and events, `cuda::copy_bytes`, and `cuda::fill_bytes`.
- CCCL 3.2 / CUDA 13.2: `cuda::launch`, hierarchy configuration, memory pools, and `cuda::buffer`.

Treat those as lookup hints, not a complete compatibility matrix. Verify compiler, driver, platform, and feature requirements for the selected release.

Use the `cuda::` Runtime interfaces, with headers such as `<cuda/devices>`, `<cuda/stream>`, `<cuda/algorithm>`, `<cuda/buffer>`, `<cuda/memory_pool>`, and `<cuda/launch>`. Distinguish these from `cuda::experimental` and `<cuda/experimental/...>` in `cudax`. The experimental library has no API or ABI stability guarantees. Do not mechanically change namespaces or substitute an experimental interface for an unavailable supported API.

Completion criterion: every selected symbol is available under the project's supported dependency configuration.

## 2. Make device and stream dependencies explicit

Select devices at the application boundary. Pass `cuda::device_ref` to code that creates device-bound resources, and `cuda::stream_ref` to code that submits work on a caller-owned stream. Use `cuda::devices` for enumeration and `device_ref` attribute queries for device properties.

Create streams with an explicit device:

```cpp
#include <cuda/devices>
#include <cuda/stream>

void submit_work(cuda::stream_ref stream);

void run_on(cuda::device_ref device) {
	cuda::stream stream{device};
	submit_work(stream);
	stream.sync();
}
```

Keep selection outside reusable helpers. Hard-coding `cuda::devices[0]` inside a helper merely replaces one hidden device choice with another. Validate externally supplied ordinals before indexing the device range.

Allocate from a pool selected for the intended device, and launch on that device's explicit stream. Trace the device of each stream, allocation, pool, and library handle through multi-GPU paths. Types make categories explicit, but do not prove that two runtime objects belong to the same GPU.

Do not add `cudaSetDevice` around CCCL Runtime operations. These operations take explicit device arguments or device-bound objects rather than consulting the CUDA Runtime current-device setting. A third-party library or retained C call may still require current-device or Driver context management. Confine that requirement to its interop boundary, preserve the caller's state where required, and check errors.

Completion criterion: every changed operation has an identifiable target device and stream without depending on unrelated caller state.

## 3. Replace operations without changing their contract

Apply the appropriate replacements within the requested change:

- Replace `cudaStreamCreate*` and manual destruction with `cuda::stream{device}`. Borrow with `cuda::stream_ref`. Replace stream synchronization and completion queries with `sync()` and `is_done()` where supported.
- Replace manual event ownership with `cuda::event`. Use `cuda::timed_event` when elapsed-time measurement is required. Verify recording and waiting signatures in the installed release.
- Prefer a device's default memory pool and `cuda::make_buffer<T>` for owned typed allocations. Use a separate pool only when the task needs different pool settings. Reuse existing suitable project containers instead of adding a competing allocation layer.
- Replace compatible byte-copy and byte-fill calls with `cuda::copy_bytes(stream, source, destination)` and `cuda::fill_bytes(stream, destination, byte_value)` from `<cuda/algorithm>`. Check destination capacity, contiguous-view requirements, and trivially copyable element requirements. `fill_bytes(..., 1)` sets every byte to `0x01`, not every integer to one. Use value initialization or a typed algorithm for element values.
- Prefer `cuda::launch(stream, config, kernel, args...)` and `cuda::distribute<BlockSize>(count)` or `cuda::make_config(...)` over manual launch plumbing where supported. Existing `__global__` kernels can remain. Explicitly instantiate kernel templates when required. Preserve shared-memory size, cooperative launch requirements, launch attributes, bounds checks, and existing empty-input behavior.

Pass raw pointers and sizes into existing kernels when that is the project convention. Adopting typed host ownership does not require changing kernel parameters. Kernel functors and automatic buffer-to-span argument transformation are options, not migration requirements.

Completion criterion: callers, ownership, error behavior, launch configuration, and observable results retain their intended contract.

## 4. Preserve lifetime, ordering, and error visibility

Apply these rules to every changed path:

- Owning types destroy their resources. `_ref` types borrow them. Use `.get()` to lend a native handle to CUB, Thrust, or another library. Use `from_native_handle` only for an intentional ownership transfer, and `.release()` only when another owner takes responsibility. Never adopt a borrowed handle.
- Keep a buffer's stored stream alive until after the buffer is destroyed. The buffer enqueues deallocation on that stream. Declare stream owners before dependent buffers, or manage destruction explicitly.
- Order allocation, initialization, use, and deallocation. If another stream uses a buffer, establish dependencies before use and before deallocation. Changing a stored stream is not a substitute for tracing all outstanding users. Check the installed `set_stream` and `destroy` contracts before using them.
- Keep host copy sources and destinations alive until asynchronous copies complete. Temporary ranges and initializer lists can expire too early. Pageable memory is not a guarantee of synchronous completion. Synchronize only at the boundary that needs completed data or must release host storage.
- Use `cuda::no_init` only when every subsequently read element is written first. Preserve existing initialization guarantees. A pool or typed buffer does not make uninitialized data safe.
- Newly created `cuda::stream` objects are non-blocking with respect to the legacy default stream. Replacing a blocking C-created stream can remove implicit ordering. Express dependencies explicitly or retain the original native stream through interop when its semantics are required.
- Treat the legacy NULL stream and per-thread default stream as interop cases. Set the intended current device before wrapping a device-dependent default stream, following NVIDIA's documented contract. Do not introduce default-stream wrappers into new explicit-device paths for convenience.
- CCCL Runtime reports failures through exceptions, including `cuda::cuda_error`. Preserve the application's error boundary. At a status-returning boundary, translate errors deliberately and handle other possible exceptions according to the boundary's contract. Do not let exceptions escape `noexcept` or a C ABI.
- Continue checking status codes for retained C APIs. CCCL launch error reporting does not prove asynchronous execution succeeded. Observe completion at the appropriate stream or event boundary. Destruction is not a substitute for an error-reporting completion check.

## 5. Keep necessary interoperability narrow

Retain a C Runtime or Driver call when the supported CCCL release lacks an equivalent, an external ABI requires it, or required semantics cannot be preserved by the C++ interface. An exception-free build may also prevent adoption of an exception-based interface.

Name the concrete limitation in the implementation or delivery report. Use existing project error handling and explicit device management at that boundary. Do not invent a similarly named CCCL API, silently upgrade dependencies, add a general compatibility layer, or rewrite unrelated working code.

The preference applies to equivalent functionality, not to a claim that NVIDIA has deprecated the entire CUDA C Runtime.

## 6. Verify through the affected boundary

Compile with the project's resolved headers and supported toolchain. Exercise the changed caller, check numerical or persisted results, and observe asynchronous completion. For multi-GPU changes, test an explicitly selected nonzero device when available. Check that allocation and launch selection still work when the CUDA current device differs from the requested target. Use a second-device test to expose accidental GPU-0 assumptions, not merely device enumeration.

If only one GPU is available, report that cross-device behavior was not verified. If hardware or headers are unavailable, report the exact validation limit rather than claiming a successful migration.

The following standalone smoke check uses the CCCL 3.2-era interfaces. It checks a non-block-aligned launch, typed allocation, raw-pointer kernel arguments, device-to-host copy, and completed results on each visible device. It does not test peer access or deliberately mismatched current-device state. Compile with the project's include configuration, C++17 or newer, and an architecture supported by the test GPU. Run without `NDEBUG` so the result assertions execute.

```cpp
#include <cuda/algorithm>
#include <cuda/buffer>
#include <cuda/devices>
#include <cuda/launch>
#include <cuda/memory_pool>
#include <cuda/std/span>
#include <cuda/stream>
#include <array>
#include <cassert>
#include <cstddef>
#include <cstdio>
#include <exception>

__global__ void write_values(int* output, std::size_t count) {
	const auto i = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
	if (i < count) {
		output[i] = static_cast<int>(i) + 7;
	}
}

int main() try {
	if (cuda::devices.size() == 0) {
		std::fputs("No CUDA devices available\n", stderr);
		return 1;
	}
	for (cuda::device_ref device : cuda::devices) {
		cuda::stream stream{device};
		auto pool = cuda::device_default_memory_pool(device);
		constexpr std::size_t count = 257;
		auto output = cuda::make_buffer<int>(stream, pool, count, cuda::no_init);
		std::array<int, count> host{};
		cuda::launch(stream, cuda::distribute<128>(count), write_values, output.data(), count);
		cuda::copy_bytes(stream, cuda::std::span<const int>{output.data(), count},
		                 cuda::std::span<int>{host.data(), host.size()});
		stream.sync();
		for (std::size_t i = 0; i < count; ++i) {
			assert(host[i] == static_cast<int>(i) + 7);
		}
	}
	return 0;
} catch (const std::exception& error) {
	std::fprintf(stderr, "%s\n", error.what());
	return 1;
}
```

Completion criterion: the affected behavior passes its narrow check, and any untested device, interop, or toolchain cases are stated explicitly.

## NVIDIA sources

Consult release-matched documentation before applying these development-documentation examples:

- [Runtime overview and API availability](https://nvidia.github.io/cccl/unstable/libcudacxx/runtime.html).
- [Device references and enumeration](https://nvidia.github.io/cccl/unstable/libcudacxx/runtime/device.html).
- [Stream ownership and synchronization](https://nvidia.github.io/cccl/unstable/libcudacxx/runtime/stream.html).
- [CUDA Runtime interoperability, exceptions, and default-stream semantics](https://nvidia.github.io/cccl/unstable/libcudacxx/runtime/cudart_interactions.html).
- [Buffer construction, asynchronous host-source lifetime, and deallocation](https://nvidia.github.io/cccl/unstable/libcudacxx/runtime/buffer.html).
- [Byte-copy and byte-fill contracts](https://nvidia.github.io/cccl/unstable/libcudacxx/runtime/algorithm.html).
- [Kernel launch and configuration](https://nvidia.github.io/cccl/unstable/libcudacxx/runtime/launch.html).
- [Experimental library stability and distribution](https://nvidia.github.io/cccl/unstable/cudax/index.html).
- [NVIDIA's CCCL Runtime introduction](https://developer.nvidia.com/blog/cccl-runtime-a-modern-c-runtime-for-cuda/).
