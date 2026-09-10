# Installing Web Swing into an existing City of Heroes server

Web Swing is a **client + MapServer source feature** with production runtime data. It is not a server-only power definition or a loose-data-only mod.

The repository contains only the Web Swing integration package, not a complete OuroDev source checkout. The normal server-owner workflow is intentionally one command:

```powershell
git clone https://github.com/coh-swing/coh-swing
cd coh-swing

powershell -ExecutionPolicy Bypass -File .\INSTALL-INTO-SERVER.ps1 `
  -TargetRepo D:\path\to\your\CoH-source
```

The installer:

1. verifies that the target looks like a CoH source tree;
2. refuses tracked local changes by default;
3. checks the complete patch before changing anything;
4. falls back to Git three-way application when safe;
5. diagnoses each subsystem separately when a fork conflicts;
6. backs up every source/runtime file it will touch;
7. applies only the generated Web Swing source patch;
8. copies the 35-file production runtime payload;
9. adds the player sequencer include exactly once;
10. verifies the installed patch, assets, exact flip windows, toggle ordering, style command, tray integration, and icon header;
11. rolls back all files touched by the run if installation or verification fails.

It does **not** run `git reset`, `git clean`, or overwrite a divergent source tree with whole files.

## Before changing anything

Use plan mode:

```powershell
.\INSTALL-INTO-SERVER.ps1 `
  -TargetRepo D:\path\to\your\CoH-source `
  -Plan
```

Possible source results:

- `NORMAL` — the patch applies directly.
- `3WAY` — Git can merge the source delta safely from the recorded baseline.
- `ALREADY` — the source patch is already present; runtime files can be repaired/reinstalled idempotently.
- conflict — **nothing is changed** and a component-by-component port report is written under the target repository's Git metadata.

## What gets installed

The generated v1 runtime payload is deliberately small:

- 29 production `.anim` dependencies;
- `cohsourcedev_webswing.inc`;
- `cohsourcedev_webswing.txt`;
- `cohsourcedev_webswing.statebits`;
- Tech anchor FX;
- Magic anchor FX;
- the final native 32×32 `COHSOURCEDEV_WebSwing_WebIcon.texture`.

Development candidates, C43–C55 audition files, captures, crash dumps, Blender projects, raw FBX files, and dev-only evidence are not part of the install payload.

## After installation

Rebuild a **matching client and MapServer** from the modified source tree. Do not mix a Web-Swing-aware MapServer with an unrelated client build.

Launch normally. Production Web Swing does not require `-webswingdev`.

Test:

```text
/webswingtoggle
```

Hold Space to swing.

Visual styles:

```text
/webswingstyle web
/webswingstyle tech
/webswingstyle magic
/webswingstyle legacy
```

The production backend is Sky-Assisted.

## Verify again later

```powershell
.\VERIFY-INSTALL.ps1 -TargetRepo D:\path\to\your\CoH-source
```

## Divergent forks

When the full patch cannot apply, the installer checks the six source components independently:

1. shared protocol/state;
2. server physics/actions;
3. client runtime;
4. animation/sequencer;
5. FX rendering;
6. player UI.

A fork may therefore need a manual merge in only one subsystem instead of forcing the operator to reverse-engineer the whole feature.

The generated report deliberately includes the failed Git context and leaves the target untouched.
