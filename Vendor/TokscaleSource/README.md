# Vendored Tokscale source

This is the buildable Rust source snapshot for `junhoyeo/tokscale` tag
`v3.0.0`, commit `c21f0f533205ad63e9154666c294bb789d2415c9`.

Included:

- `tokscale-core`, containing local session scanners, parsers, aggregation,
  pricing, and cache handling.
- `tokscale-cli`, containing the graph export command and Antigravity RPC
  integration used by ToolbarMonitor's embedded collector.
- The workspace manifests, locked dependency versions, and MIT license.

The web frontend, screenshots, packaging wrappers, and unrelated repository
automation are intentionally omitted. The source can be rebuilt from this
directory with:

```sh
cargo build --release -p tokscale-cli
```

ToolbarMonitor does not compile this snapshot during an Xcode build. The app
ships the corresponding official universal macOS executable from
`ToolbarMonitor/Resources/UsageCollectorBackend`.
