"""
Hyprland/Wayland repaint workaround for smart_split.

This module forces a compositor repaint after creating a split to avoid
transient right/bottom clipping observed on Hyprland with kitty in Wayland mode.
"""

from __future__ import annotations

import os
import subprocess
import time

from kitty.constants import is_wayland

_HYPRLAND_WAYLAND_SPLIT_WORKAROUND_ENV = "KITTY_HYPRLAND_WAYLAND_SPLIT_WORKAROUND"
_HYPRLAND_WAYLAND_SPLIT_DEBUG_ENV = "KITTY_HYPRLAND_WAYLAND_SPLIT_DEBUG"


def _is_hyprland_wayland() -> bool:
    return is_wayland() and bool(os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"))


def _split_repaint_log(message: str) -> None:
    if os.environ.get(_HYPRLAND_WAYLAND_SPLIT_DEBUG_ENV, "0").strip().lower() not in (
        "1",
        "true",
        "yes",
        "on",
    ):
        return

    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime_dir:
        return

    try:
        with open(
            os.path.join(runtime_dir, "kitty-hyprland-split-workaround.log"),
            "a",
            encoding="utf-8",
        ) as f:
            f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {message}\n")
    except Exception:
        return


def _hyprctl_json(*args: str) -> dict:
    """
    Return hyprctl JSON output as a dict.

    This is used to read the active window address and enumerate candidates on
    the same workspace.
    """
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
    """
    Run a hyprctl dispatcher command.

    Dispatchers are scoped to focus transitions and the renderer reload fallback.
    """
    proc = subprocess.run(
        ["hyprctl", "dispatch", *args],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            proc.stderr.strip() or f"hyprctl dispatch {' '.join(args)} failed"
        )


def split_repaint_focus_bounce() -> None:
    """
    Trigger a compositor repaint after split creation on Hyprland/Wayland.

    A focus bounce within the same workspace is preferred; monitor bounce and
    renderer reload are used as fallbacks.
    """
    setting = (
        os.environ.get(_HYPRLAND_WAYLAND_SPLIT_WORKAROUND_ENV, "1").strip().lower()
    )
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

        # Prefer focusing another window on the same workspace to avoid
        # workspace-switch animations.
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
            _hyprctl_dispatch("focuswindow", f"address:{candidate_address}")
            _hyprctl_dispatch("focuswindow", f"address:{address}")
            _split_repaint_log(
                f"ok: focus_bounce address={address} via={candidate_address}"
            )
        else:
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
