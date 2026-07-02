---
name: cuda-meson-subproject-patch
description: Patches Meson wrap subprojects so NVCC/C++20 CUDA builds succeed, using packagefiles and wrap metadata. Use when `meson compile` fails inside `subprojects/` after a fresh wrap fetch, or upstream headers need fixes under `subprojects/packagefiles/<name>/`.
---

# CUDA Meson subproject patch

## Quick start

```bash
meson setup build --wipe
meson compile -C build
```

Patches: **`subprojects/packagefiles/<subproject>/`** + **`subprojects/<name>.wrap`** (`patch_directory`, `diff_files`).

## Workflows

### Reproduce

- Capture the **first** NVCC error location in upstream subproject sources.
- Check whether fixes exist only in a dirty `subprojects/<name>/` tree (lost on re-wrap).

### Author patch

```bash
cd subprojects/<name>
diff -u a/include/header.hpp b/include/header.hpp > \
  ../packagefiles/<name>/descriptive-fix.patch
```

Wire `.wrap`:

```ini
patch_directory = <name>
diff_files = <name>/descriptive-fix.patch
```

Override `packagefiles/<name>/meson.build` when CUDA flags or targets differ.

### Verify clean fetch

```bash
rm -rf subprojects/<name> build
meson setup build && meson compile -C build
```

Compile one failing target with `ninja -C build <target>` first.

## Pitfalls

- Wrap download alone does **not** apply hand-edited subproject trees.
- Regenerate corrupt patches with `diff -u`. bad hunk counts break `git apply -p1`.
- NVCC exposes template bugs host GCC never compiled.
