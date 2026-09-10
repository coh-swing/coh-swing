# Integration package layout

This directory is the complete source/runtime handoff for C55 Web Swing.

```text
integration/
  manifest.json                 source patch metadata and component map
  asset-manifest.json           runtime payload hashes
  source-files.json             curated list of touched source files
  webswing-v1.patch             complete source integration patch
  patches/                      same source patch split by subsystem
  payload/                      35 production runtime files
```

The repository does **not** include complete copies of the 29 source files named by the manifest. `webswing-v1.patch` and `patches/` contain only the Web Swing diffs to apply to an existing source checkout.

Use `../INSTALL-INTO-SERVER.ps1` for the normal install path or `../PORTING-GUIDE.md` for a manual port into a divergent fork.

