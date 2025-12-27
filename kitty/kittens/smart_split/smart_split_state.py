"""
State management for the smart_split kitten.

This module tracks per-window state (size deltas and ordering) and provides
helpers for waiting on window list changes after split or close actions.
"""

from __future__ import annotations

import time

from kitty.typing_compat import BossType

from smart_split_kitty import tab_window_ids


def ensure_state(
    boss: BossType,
    state_key: int | str,
    width_delta: int,
    height_delta: int,
) -> dict:
    """
    Ensure a state dict exists for the given key and return it.

    State is keyed by OS window id when available to prevent cross-window leakage.
    """
    state_store = getattr(boss, "_smart_split_state", None)
    if state_store is None:
        state_store = {}
        setattr(boss, "_smart_split_state", state_store)
    state = state_store.setdefault(
        state_key,
        {
            "expanded": False,
            "width_delta": width_delta,
            "height_delta": height_delta,
            "order": [],
        },
    )
    if not isinstance(state.get("order"), list):
        state["order"] = []
    return state


def wait_for_window_ids_change(tab, previous_ids: list[int]) -> list[int]:
    """
    Wait briefly for a split or close to update the window list.

    This avoids racing the layout normalization step while the tab is mid-update.
    """
    current_ids = previous_ids
    previous_set = set(previous_ids)
    for _ in range(20):
        # Poll in short intervals to keep close/split latency low.
        current_ids = tab_window_ids(tab)
        if set(current_ids) != previous_set or len(current_ids) != len(previous_ids):
            return current_ids
        time.sleep(0.03)
    return current_ids


def wait_for_window_ids_settle(tab) -> list[int]:
    """
    Wait for the window list to stop changing between polling intervals.

    This is used for the explicit normalize mode where the layout should be stable.
    """
    current_ids = tab_window_ids(tab)
    for _ in range(12):
        # A brief pause gives kitty time to finish the layout update.
        time.sleep(0.03)
        next_ids = tab_window_ids(tab)
        if next_ids == current_ids:
            return current_ids
        current_ids = next_ids
    return current_ids


def sync_window_order(
    state: dict,
    current_ids: list[int],
    new_ids: list[int] | None = None,
    previous_ids: list[int] | None = None,
) -> list[int]:
    """
    Preserve stable creation order so layout slots remain predictable.

    New windows are appended, while removed ids are filtered out.
    """
    order = state.get("order")
    if not isinstance(order, list):
        order = []
    if not order and previous_ids:
        order = [wid for wid in previous_ids if wid in current_ids]
    else:
        order = [wid for wid in order if wid in current_ids]
    if new_ids:
        for wid in new_ids:
            if wid in current_ids and wid not in order:
                order.append(wid)
    for wid in current_ids:
        if wid not in order:
            order.append(wid)
    state["order"] = order
    return order
