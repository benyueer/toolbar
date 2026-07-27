# Embedded usage collector

This directory vendors the native local-usage collector built from
[`junhoyeo/tokscale`](https://github.com/junhoyeo/tokscale) tag `v3.0.0`,
commit `c21f0f533205ad63e9154666c294bb789d2415c9`.

The universal macOS executable combines the official x86_64 and arm64 builds
from:

- `@tokscale/cli-darwin-x64@3.0.0`
- `@tokscale/cli-darwin-arm64@3.0.0`

The corresponding buildable Rust source is vendored at
`Vendor/TokscaleSource` for offline review and reproducible rebuilding.

ToolbarMonitor invokes this vendored executable directly. It does not search
for or execute a separately installed `tokscale` command. Runtime state is
redirected to ToolbarMonitor's own Application Support directory.

The upstream project is licensed under the MIT License. A copy is included in
`LICENSE`.
