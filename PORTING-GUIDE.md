# Porting C55 Web Swing into another City of Heroes source tree

This guide is for server owners who want to integrate the complete Web Swing feature into an existing OuroDev-derived fork.

The easiest path is the installer. The manual path below exists so a maintainer can understand and merge the feature cleanly when their fork has diverged.

## What is included

The package preserves the complete production feature:

- `/webswingtoggle`;
- Sky-Assisted swing physics;
- hold-Space swing input and release behavior;
- chained swing momentum and stunt behavior;
- C55 production animation under `COHSOURCEDEV_WEBSWING_MAIN_V1`;
- exact front/back stunt animation windows;
- Male, Female, and Huge animation sets;
- WEB, TECH, MAGIC, and LEGACY visual styles;
- Tech/Magic anchor FX;
- the Web Swing tray macro/icon; and
- the production state-bit/sequencer overlay.

No OuroDev source tree is bundled. The source portion is represented as patches only.

## Requirements

You need:

1. an OuroDev-derived City of Heroes source checkout in Git;
2. the normal runtime data materialized under that checkout, including `bin/data/sequencers/player.txt`;
3. a build environment capable of rebuilding both the client and MapServer; and
4. preferably a clean target working tree before installing.

## Option A: automatic install

From this repository:

```powershell
.\INSTALL-INTO-SERVER.ps1 -TargetRepo D:\path\to\your\CoH-source -Plan
```

If the plan reports `NORMAL`, `3WAY`, or `ALREADY`, install with:

```powershell
.\INSTALL-INTO-SERVER.ps1 -TargetRepo D:\path\to\your\CoH-source
```

The installer validates the full source patch and all runtime hashes before changing the target. On a source conflict it writes a component-by-component report and leaves the target unchanged.

## Option B: manual source port

The full source patch is:

```text
integration/webswing-v1.patch
```

For a close OuroDev fork, first try:

```powershell
git -C D:\path\to\your\CoH-source apply --check D:\path\to\coh-swing\integration\webswing-v1.patch
```

If that passes:

```powershell
git -C D:\path\to\your\CoH-source apply D:\path\to\coh-swing\integration\webswing-v1.patch
```

If the full patch conflicts, port the six components in order. Each file contains only the relevant source diff for that subsystem.

### 1. Shared protocol and control state

Patch:

```text
integration/patches/001-shared-protocol.patch
```

Files touched:

```text
Common/cmdparse/cmdcommon.c
Common/cmdparse/cmdcommon.h
Common/cmdparse/cmdcontrols.h
Common/cmdparse/cmdenum.h
Common/entity/motion.h
```

Purpose: defines the shared Web Swing command/control state used by both client and MapServer. Keep client and server layouts synchronized.

### 2. Server physics and actions

Patch:

```text
integration/patches/002-server-physics.patch
```

Files touched:

```text
Common/entity/entworldcoll.c
Common/entity/entworldcoll.h
Common/entity/motion.c
Common/player/pmotion.c
MapServer/src/cmdparse/cmdserver.c
MapServer/src/entity/entGameActions.c
MapServer/src/entity/entGameActions.h
MapServer/src/svr/svr_init.c
MapServer/src/svr/svr_player.c
```

Purpose: implements anchor acquisition, Sky-Assisted movement, momentum/release behavior, server toggle actions, and replication of the Web Swing control state.

Important production ordering when enabling Web Swing is:

```c
setWebSwingBackend(e, 1);
setWebSwing(e, 1);
```

### 3. Client runtime and presentation

Patch:

```text
integration/patches/003-client-runtime.patch
```

Files touched:

```text
Game/src/cmdparse/cmdgame.c
Game/src/entity/entclient.c
Game/src/entity/entclient.h
Game/src/game.c
Game/src/graphics/gfx.c
Game/src/main.c
Game/src/player/player.c
Common/player/pmotion.h
```

Purpose: receives the replicated state, drives the finalized animation synchronization, draws the tether/anchor presentation, supports the visual-style commands, and installs the player-facing tray macro.

### 4. Animation and sequencer support

Patch:

```text
integration/patches/004-animation-sequencer.patch
```

Files touched:

```text
Common/seq/TriggeredMove.h
Common/seq/seqload.c
Common/seq/seqsequence.c
Common/seq/seqstate.c
```

Purpose: loads the private Web Swing state-bit namespace and overlays the production Web Swing moves onto the normal player sequencer in a release client.

Do not rename or replace the production animation alias:

```text
COHSOURCEDEV_WEBSWING_MAIN_V1
```

The packaged Male production selection is the accepted C55 two-hand-grip candidate.

### 5. FX rendering support

Patch:

```text
integration/patches/005-fx-rendering.patch
```

Files touched:

```text
Common/fxinfo.c
Game/src/graphics/FX/particle.c
```

Purpose: permits the namespaced packaged Web Swing Tech/Magic FX to resolve in a normal release client without globally enabling loose-development FX behavior.

### 6. Player UI state

Patch:

```text
integration/patches/006-player-ui.patch
```

File touched:

```text
Game/src/UI/uiTray.c
```

Purpose: lets the Web Swing tray macro reflect whether Web Swing is currently active.

## Install the runtime payload

After the source changes are merged, copy the contents of:

```text
integration/payload/
```

into the root of the target source/runtime checkout, preserving paths.

The payload contains 35 production files, including 29 animation dependencies, the Web Swing sequencer/state-bit files, Tech/Magic anchor FX, and the native Web Swing icon.

Then add this line **exactly once** to:

```text
bin/data/sequencers/player.txt
```

```text
include sequencers/cohsourcedev_webswing.inc
```

## Rebuild

Rebuild a matching client and MapServer from the modified source tree. Do not pair a Web-Swing-aware MapServer with a client built from an unrelated source state.

## Verify

From this repository:

```powershell
.\VERIFY-INSTALL.ps1 -TargetRepo D:\path\to\your\CoH-source
```

The verifier checks the source patch, runtime hashes, all 29 animation dependencies, player include, exact stunt windows, Sky-Assisted enable ordering, visual-style command, tray integration, and icon header.

## Playtest

Launch normally; `-webswingdev` is not required.

Use:

```text
/webswingtoggle
```

Hold Space to swing. Test chained swings and release momentum, then verify all four visual styles:

```text
/webswingstyle web
/webswingstyle tech
/webswingstyle magic
/webswingstyle legacy
```

## Porting rule for divergent forks

When a component conflicts, merge the patch into that fork's existing implementation. Do **not** replace the fork's complete `.c` or `.h` file with a file from another OuroDev revision. The component patches are intentionally provided so the Web Swing delta can be reviewed and transplanted without overwriting unrelated server work.

