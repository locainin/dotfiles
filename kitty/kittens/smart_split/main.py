#!/usr/bin/env python3
# smart split kitten: enforce max splits, manage window sizing, and guide layout flow

from __future__ import annotations

"""
smart_split kitten

Primary responsibilities:
- Create controlled split layouts (max N panes per tab) with predictable placement.
- Expand/shrink the OS window slightly to preserve usable cell geometry when going
  from 1 pane → multiple panes (and reverse it when returning to 1 pane).

Hyprland/Wayland rendering issue (workaround implemented here):
- Observed on kitty (native Wayland) under Hyprland at scale=1.0:
  Immediately after creating a new pane, the right/bottom edges of panes can be
  clipped/misaligned. The render corrects itself after the kitty OS window loses
  focus (commonly triggered by pointer focus leaving the window).

Working hypothesis:
- A compositor/client damage/repaint synchronization bug causes Hyprland to miss
  a final repaint of the newly configured split viewport until a later focus
  transition forces a full repaint.

Mitigation:
- After creating a new pane, trigger a compositor-level repaint by performing a
  Hyprland focus round-trip within the *same workspace*:
    1) Focus a different mapped window on the same workspace (if one exists)
    2) Immediately refocus the original kitty window by Hyprland address
- If no other mapped window exists on the workspace, fall back to:
    a) focusmonitor bounce (current monitor) + refocus the kitty window
    b) hyprctl dispatch forcerendererreload
  which forces a repaint without requiring a second window.

Scope, safety, and operational controls:
- Applied only on Hyprland + Wayland (gated by Wayland detection and the
  HYPRLAND_INSTANCE_SIGNATURE environment variable).
- Can be disabled with KITTY_HYPRLAND_WAYLAND_SPLIT_WORKAROUND=0.
- Debug logging (opt-in) via KITTY_HYPRLAND_WAYLAND_SPLIT_DEBUG=1 writes to:
  $XDG_RUNTIME_DIR/kitty-hyprland-split-workaround.log
"""

import os
import subprocess
import time

from kittens.tui.handler import result_handler
from kitty.constants import is_wayland
from kitty.typing_compat import BossType

WIDTH_DELTA_CELLS = 8
HEIGHT_DELTA_CELLS = 4

_HYPRLAND_WAYLAND_SPLIT_WORKAROUND_ENV = "KITTY_HYPRLAND_WAYLAND_SPLIT_WORKAROUND"
_HYPRLAND_WAYLAND_SPLIT_DEBUG_ENV = "KITTY_HYPRLAND_WAYLAND_SPLIT_DEBUG"


def _is_hyprland_wayland() -> bool:
    return is_wayland() and bool(os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"))


def _split_repaint_log(message: str) -> None:
    if os.environ.get(_HYPRLAND_WAYLAND_SPLIT_DEBUG_ENV, "0").strip().lower() not in ("1", "true", "yes", "on"):
        return

    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime_dir:
        return

    try:
        with open(os.path.join(runtime_dir, "kitty-hyprland-split-workaround.log"), "a", encoding="utf-8") as f:
            f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {message}\n")
    except Exception:
        return


def _hyprctl_json(*args: str) -> dict:
    # hyprctl JSON output is used to:
    # - Read the currently focused window address (activewindow)
    # - Enumerate candidates on the same workspace (clients)
    proc = subprocess.run(
        ["hyprctl", "-j", *args],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or f"hyprctl -j {' '.join(args)} failed")
    import json

    return json.loads(proc.stdout)


def _hyprctl_dispatch(*args: str) -> None:
    # Hyprland dispatcher invocations are intentionally minimal and scoped:
    # - focuswindow address:<addr> (focus bounce within same workspace)
    # - forcerendererreload (last resort, no focus change)
    proc = subprocess.run(
        ["hyprctl", "dispatch", *args],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or f"hyprctl dispatch {' '.join(args)} failed")


def _split_repaint_focus_bounce() -> None:
    setting = os.environ.get(_HYPRLAND_WAYLAND_SPLIT_WORKAROUND_ENV, "1").strip().lower()
    if setting in ("0", "false", "no", "off"):
        return

    if not _is_hyprland_wayland():
        return

    try:
        active = _hyprctl_json("activewindow")
        address = active.get("address")
        workspace = active.get("workspace") or {}
        workspace_id = workspace.get("id")
        if not address:
            _split_repaint_log("skip: activewindow missing address")
            return

        # Prefer focusing another window on the *same workspace* to avoid triggering
        # workspace switch animations.
        #
        # Previous approach used `focuscurrentorlast`, which can pick a window on a
        # different workspace; on animated configs this looks like the OS window is
        # "sliding" in/out. Constraining to same-workspace candidates removes that.
        #
        # Selection strategy:
        # - Choose the most recently focused candidate on the same workspace
        #   (smallest focusHistoryID other than the active window).
        candidate_address: str | None = None
        if isinstance(workspace_id, int):
            clients = _hyprctl_json("clients")
            candidates: list[tuple[int, str]] = []
            for c in clients:
                try:
                    if not c.get("mapped", True) or c.get("hidden", False):
                        continue
                    if (c.get("workspace") or {}).get("id") != workspace_id:
                        continue
                    addr = c.get("address")
                    if not addr or addr == address:
                        continue
                    hid = int(c.get("focusHistoryID", 10**9))
                    candidates.append((hid, addr))
                except Exception:
                    continue
            if candidates:
                candidates.sort(key=lambda x: x[0])
                candidate_address = candidates[0][1]

        if candidate_address:
            # Compositor-level repaint via focus transition. This mirrors the manual
            # workaround (pointer focus leaving the window) without changing the
            # workspace or the final focused window.
            _hyprctl_dispatch("focuswindow", f"address:{candidate_address}")
            _hyprctl_dispatch("focuswindow", f"address:{address}")
            _split_repaint_log(f"ok: focus_bounce address={address} via={candidate_address}")
        else:
            # When no other mapped window exists on the workspace (for example,
            # kitty is the only window and is effectively fullscreen), a normal
            # focus bounce is not possible. In that situation:
            # 1) Try a monitor focus "bounce" and then refocus the window. This
            #    can trigger the same focus-driven repaint without involving a
            #    different workspace or a second window.
            # 2) Fall back to forcing a renderer reload (heavier, but does not
            #    rely on focus state changes being possible).
            try:
                _hyprctl_dispatch("focusmonitor", "current")
                _hyprctl_dispatch("focuswindow", f"address:{address}")
                _split_repaint_log(f"ok: focusmonitor_bounce address={address}")
            except Exception as e:
                _split_repaint_log(f"warn: focusmonitor_bounce failed: {e!s}")

            _hyprctl_dispatch("forcerendererreload")
            _split_repaint_log(f"ok: forcerendererreload address={address}")
    except Exception as e:
        _split_repaint_log(f"error: {e!s}")
        return


def main(args: list[str]) -> list[str]:
    # parameters are handled in handle_result
    return args


def _active_tab_manager(boss: BossType):
    attr = getattr(boss, 'active_tab_manager', None)
    if callable(attr):
        try:
            return attr()
        except Exception:
            return None
    return attr


def _active_tab(boss: BossType):
    attr = getattr(boss, 'active_tab', None)
    if callable(attr):
        try:
            return attr()
        except Exception:
            return None
    return attr


def _window_count(tab) -> int:
    try:
        return len(tab.windows)
    except Exception:
        return 0


@result_handler(no_ui=True)
def handle_result(args: list[str], answer: object, target_window_id: int, boss: BossType) -> None:
    max_windows = 4
    orientation = 'auto'
    mode = 'split'

    if args:
        try:
            max_windows = int(args[0])
        except Exception:
            pass
        if len(args) > 1 and args[1] in ('hsplit', 'vsplit', 'auto'):
            orientation = args[1]
        if len(args) > 2 and args[2] in ('split', 'grow', 'shrink', 'close_window', 'close_tab'):
            mode = args[2]

    tab = _active_tab(boss)
    if tab is None:
        return

    tm = _active_tab_manager(boss)
    os_window_id = getattr(tm, 'os_window_id', None) if tm is not None else None
    window_count = _window_count(tab)

    state_store = getattr(boss, '_smart_split_state', None)
    if state_store is None:
        state_store = {}
        setattr(boss, '_smart_split_state', state_store)
    state_key = os_window_id if os_window_id is not None else '__default__'
    state = state_store.setdefault(
        state_key,
        {
            'expanded': False,
            'width_delta': WIDTH_DELTA_CELLS,
            'height_delta': HEIGHT_DELTA_CELLS,
        },
    )

    if mode in ('shrink', 'close_window', 'close_tab'):
        if mode == 'close_window' and window_count <= 1:
            return
        should_shrink = state['expanded'] and window_count <= 2 and os_window_id is not None
        if should_shrink:
            try:
                boss.resize_os_window(
                    os_window_id,
                    width=-state['width_delta'],
                    height=-state['height_delta'],
                    unit='cells',
                    incremental=True,
                )
            except Exception:
                pass
            else:
                state['expanded'] = False
        if mode == 'close_window':
            try:
                boss.close_window()
            finally:
                try:
                    tab.reset_window_sizes()
                except Exception:
                    pass
        elif mode == 'close_tab':
            try:
                boss.close_tab()
            finally:
                state['expanded'] = False
        return

    if mode not in ('split', 'grow'):
        return

    if window_count >= max_windows:
        return

    try:
        boss.call_remote_control(None, ('goto-layout', 'splits'))
    except Exception:
        pass

    chosen = orientation if orientation != 'auto' else 'vsplit'
    rotate_root = False
    move_bottom = False
    focus_before_split: str | None = None

    if orientation == 'auto':
        if window_count == 1:
            chosen = 'vsplit'  # first split: left/right
        elif window_count == 2:
            # create a brand-new pane, then move THAT pane to the bottom edge
            chosen = 'hsplit'
            move_bottom = True
        elif window_count == 3:
            chosen = 'vsplit'
            focus_before_split = 'down'
        else:
            chosen = 'vsplit' if window_count % 2 == 0 else 'hsplit'

    if window_count == 1 and os_window_id is not None and not state['expanded']:
        try:
            boss.resize_os_window(
                os_window_id,
                width=state['width_delta'],
                height=state['height_delta'],
                unit='cells',
                incremental=True,
            )
        except Exception:
            pass
        else:
            state['expanded'] = True

    if rotate_root:
        try:
            # correct RC form: generic 'action' + 'layout_action' + 'rotate'
            boss.call_remote_control(None, ('action', 'layout_action', 'rotate'))
        except Exception:
            pass

    if focus_before_split:
        try:
            boss.call_remote_control(None, ('action', 'neighboring_window', focus_before_split))
        except Exception:
            pass

    launch_args = ['--cwd=current', f'--location={chosen}']
    if window_count >= 1:
        launch_args.append('--env=KITTY_SUPPRESS_BANNER=1')
    boss.launch(*launch_args)

    if move_bottom:
        try:
            boss.call_remote_control(None, ('action', 'layout_action', 'move_to_screen_edge', 'bottom'))
        except Exception:
            pass

    try:
        tab.reset_window_sizes()
    except Exception:
        pass

    # Force an immediate repaint after split creation on Hyprland/Wayland to avoid
    # the transient right/bottom-edge clip until OS-window focus changes.
    _split_repaint_focus_bounce()
