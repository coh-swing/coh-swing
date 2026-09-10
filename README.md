# City of Heroes Web Swing

Portable C55 Web Swing integration for OuroDev-derived City of Heroes servers.

This repository is intentionally **not a copy of the OuroDev source tree**. It contains only the files needed to port Web Swing into an existing source checkout:

- the installer and verifier;
- the complete Web Swing source diff, split into six reviewable subsystem patches;
- the 35-file production runtime payload;
- manifests used for integrity checks and conflict reporting; and
- a manual porting guide for divergent forks.

The production package preserves the full feature set: C55 animation, Sky-Assisted swing physics, WEB / TECH / MAGIC / LEGACY visuals, tray icon integration, front/back stunt windows, and Male/Female/Huge animation support.

## Recommended install

```powershell
git clone https://github.com/coh-swing/coh-swing
cd coh-swing

.\INSTALL-INTO-SERVER.ps1 -TargetRepo D:\path\to\your\CoH-source
```

Before changing anything, you can preview compatibility:

```powershell
.\INSTALL-INTO-SERVER.ps1 -TargetRepo D:\path\to\your\CoH-source -Plan
```

The installer does not run `git reset` or `git clean`. It checks the patch first, backs up every touched file, installs the runtime payload, adds the player sequencer include once, verifies the result, and rolls back its changes if verification fails.

After installation, rebuild a matching **client and MapServer**, launch normally, and use:

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

## Manual porting

If your fork is too different for `git apply`, follow [PORTING-GUIDE.md](PORTING-GUIDE.md). The six component patches let you port only the subsystem that conflicts instead of copying whole source files.

## What "29 source files" means

The integration patch modifies 29 files **inside your existing City of Heroes source checkout**. Those 29 complete source files are not shipped here. This repository ships only the diffs needed to add Web Swing to them.

