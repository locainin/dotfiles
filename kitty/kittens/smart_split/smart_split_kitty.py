"""
Kitty API helpers for the smart_split kitten.

This module isolates kitty-specific access patterns (Boss, Tab, Window) so the
entrypoint can focus on flow control and layout rules.
"""

from __future__ import annotations

from kitty.typing_compat import BossType


def active_tab_manager(boss: BossType):
    """Return the active tab manager, handling callable or attribute forms."""
    attr = getattr(boss, "active_tab_manager", None)
    if callable(attr):
        try:
            return attr()
        except Exception:
            return None
    return attr


def active_tab(boss: BossType):
    """Return the active tab, handling callable or attribute forms."""
    attr = getattr(boss, "active_tab", None)
    if callable(attr):
        try:
            return attr()
        except Exception:
            return None
    return attr


def window_count(tab) -> int:
    """Return the current window count for the tab, defaulting to 0 on errors."""
    try:
        return len(tab.windows)
    except Exception:
        return 0


def tab_window_ids(tab) -> list[int]:
    """
    Return window ids in a stable order, preferring ids derived from tab iteration.

    The id list is used to keep layout slots deterministic across splits and closes.
    """
    try:
        return [w.id for w in tab]
    except Exception:
        pass
    try:
        return [
            w.get("id")
            for w in tab.list_windows()
            if isinstance(w, dict) and w.get("id") is not None
        ]
    except Exception:
        return []


def active_window_neighbors(tab) -> dict:
    """
    Return neighbor metadata for the active window, if the layout exposes it.

    Neighbor metadata can be absent on some kitty versions or layouts.
    """
    try:
        active_window = getattr(tab, "active_window", None)
        active_window_id = getattr(active_window, "id", None)
        if active_window_id is None:
            return {}
        list_windows = getattr(tab, "list_windows", None)
        if not callable(list_windows):
            return {}
        for window_info in list_windows():
            if window_info.get("id") == active_window_id:
                return window_info.get("neighbors") or {}
    except Exception:
        return {}
    return {}


def close_active_window(boss: BossType, target_window_id: int) -> None:
    """
    Close the window that invoked the kitten, falling back to remote control.

    The explicit id ensures the close applies to the launcher even if focus moves.
    """
    try:
        boss.mark_window_for_close(target_window_id)
        return
    except Exception:
        pass
    try:
        boss.close_window()
        return
    except Exception:
        pass
    try:
        boss.call_remote_control(None, ("action", "close_window"))
        return
    except Exception:
        return


def window_group_id(tab, window_id: int) -> int | None:
    """
    Return the window group id for the splits layout tree, when available.

    Group ids provide stable references for layout serialization.
    """
    try:
        window = tab.windows.id_map.get(window_id)
        if window is None:
            return None
        group = tab.windows.group_for_window(window)
        return group.id if group is not None else None
    except Exception:
        return None
