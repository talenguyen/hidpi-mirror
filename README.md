# hidpi-mirror

Tiny macOS command-line tool that makes an external **1080p monitor** readable on an
**Apple Silicon** Mac by running it in HiDPI "looks like 1600x900": macOS renders 3200x1800 and
downsamples it to the panel's native 1920x1080. No BetterDisplay or other app needed.

## Who it is for

- You have a Mac with Apple Silicon and an external 1920x1080 monitor (typically 22-24").
- macOS only offers that monitor 1x modes, so text looks coarse and the "scaled" resolutions in
  System Settings > Displays do not include a HiDPI option.
- You are comfortable building a small Swift package and running a shell script.

Not for you if you use 4K or 5K displays (macOS already offers HiDPI there) or an Intel Mac
(untested).

## How it works

It creates a virtual display (private `CGVirtualDisplay` API) with a single 1600x900 HiDPI mode
and mirrors your external display from it. A small background process holds the virtual display
alive and re-applies the mirror after unplug/replug, sleep/wake or any display reconfiguration.
The built-in display is never touched.

## Install with an AI agent

Not comfortable with the terminal? Paste this prompt into Claude Code, Codex or Cursor on your Mac:

```text
Please install the open-source tool hidpi-mirror on this Mac for me, so my external
1080p monitor shows bigger, easier-to-read text. Repo:
https://github.com/talenguyen/hidpi-mirror

Do it step by step and explain each step in plain, simple words:

1. Check this Mac fits: Apple Silicon (M1/M2/M3/M4) and an external monitor running
   at 1920x1080 (use `system_profiler SPDisplaysDataType`). If it does not fit,
   stop and tell me why. Don't install anything.
2. If the Xcode Command Line Tools are missing, run `xcode-select --install` and
   tell me to click "Install" in the popup, then wait for me.
3. Clone the repo into ~/Tools/hidpi-mirror. Read README.md and scripts/install.sh
   first, then tell me in 2-3 sentences what the script changes on my Mac.
4. Run ./scripts/install.sh. Don't use sudo.
5. Verify: `system_profiler SPDisplaysDataType` should show my external monitor
   with "UI Looks like: 1600 x 900". The built-in screen must stay unchanged.
6. If `hidpi-mirror` is not found as a command, add ~/.local/bin to my PATH in
   ~/.zshrc.
7. Finally, tell me the 3 commands I need: `hidpi-mirror off` (back to normal),
   `hidpi-mirror on` (turn it back on), and how to uninstall
   (./scripts/uninstall.sh in ~/Tools/hidpi-mirror).

If anything fails, stop, show me the error, and don't try risky fixes.
```

## Install

Needs the Xcode Command Line Tools (or Xcode). If they are missing, the script tells you to run
`xcode-select --install`.

```sh
git clone https://github.com/talenguyen/hidpi-mirror.git
cd hidpi-mirror
./scripts/install.sh
```

The script runs `swift build -c release`, then writes only:

- `~/.local/bin/hidpi-mirror`
- `~/Library/LaunchAgents/local.hidpi-mirror.plist` (runs `hidpi-mirror run` at login, restarts
  after a crash; generated from `launchd/local.hidpi-mirror.plist.template` with your home path)
- `~/Library/Logs/hidpi-mirror.log`

Nothing is downloaded and no prebuilt binary is shipped: you build the code you can read.

## Use

```sh
hidpi-mirror status   # displays, modes, mirror state; exit 0 = ON, 3 = OFF
hidpi-mirror off      # stop the agent: mirror released, virtual display removed, back to native
hidpi-mirror on       # start it again
hidpi-mirror run      # foreground (what the LaunchAgent runs); Ctrl-C = off
```

`off` lasts until the next login (the LaunchAgent starts again at login). To disable permanently,
uninstall.

Options (for `run`/`status`; to change them for the agent, edit `ProgramArguments` in the plist
and reload it with `launchctl bootout gui/$(id -u)/local.hidpi-mirror` then
`launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.hidpi-mirror.plist`):

| Flag | Default | Meaning |
| --- | --- | --- |
| `--size WxH` | `1600x900` | "Looks like" size. Keep it 16:9 for a 1080p panel or the picture is letterboxed. `1440x810` is slightly smaller, `1280x720` has larger text. |
| `--vendor HEX` | `any` | EDID vendor of the display to scale (`10ac` = Dell). `any` picks the first external display. Use it to pick one monitor when several are connected. |
| `--hz N` | `60` | Refresh rate of the virtual display. |

Only one external display is scaled at a time.

## Uninstall

```sh
./scripts/uninstall.sh
```

Stops the agent (the monitor returns to native 1920x1080) and deletes the three files above.
Manual equivalent:

```sh
launchctl bootout gui/$(id -u)/local.hidpi-mirror
rm ~/Library/LaunchAgents/local.hidpi-mirror.plist ~/.local/bin/hidpi-mirror ~/Library/Logs/hidpi-mirror.log
```

## Known side effects and limits

- When it starts, the screen flickers for a second or two and windows/cursor can jump: the
  external display becomes a mirror of a virtual display, so System Settings > Displays shows the
  mirror set, not a separate entry for your monitor. The monitor cannot be arranged independently
  of the virtual display.
- A "HiDPI Mirror 1600x900" display exists while it is on (visible in System Settings and
  `system_profiler`). It disappears on `off`/quit/crash; the mirror is session-only (nothing is
  written to the display preferences).
- Colour: the virtual display advertises generic RGB primaries; the monitor's own ICC profile may
  no longer be the one applied (not measured).
- `CGVirtualDisplay` is a private API. A macOS update can change or remove it; if `status` stays
  OFF after an update and the log says "failed to create virtual display", this approach is broken
  until the shim in `Sources/CVirtualDisplay` is updated. `off`/uninstall always works.
- The mode is not available in stock macOS for the tested monitor (the HiDPI 1600x900 entry
  disappears from its mode list as soon as it is switched to 1920x1080). The documented
  alternative, a display-override plist in `/Library/Displays/...`, needs sudo, is system wide and
  was not tried.
- Re-apply after a physical unplug/replug follows the same code path as the tested cases
  (external mirror removal, kill -9 + LaunchAgent restart) but a real cable pull was not tested.

## Tested on

| Mac | macOS | Monitor | Connection | Result |
| --- | --- | --- | --- | --- |
| Apple M4 | 26.3.1 | Dell P2319H (1920x1080) | DisplayPort | works |

Anything else is untested. Reports are welcome as issues.

## Development

```sh
swift build && swift test        # unit tests: size parsing, target selection, reconcile decisions
HIDPI_MIRROR_DEBUG=1 .build/debug/hidpi-mirror run
```

## Licence and attribution

MIT, see `LICENSE`. `THIRD_PARTY_NOTICES.md` carries the BetterDummy (MIT) attribution covering
the CGVirtualDisplay declarations. Clean-room: no code or binaries from the closed-source
BetterDisplay were read or used.

## No warranty

This tool uses an undocumented system API and changes your display configuration. It is provided
as is, without warranty of any kind (see `LICENSE`). Use it at your own risk; `./scripts/uninstall.sh`
restores the normal display setup.
