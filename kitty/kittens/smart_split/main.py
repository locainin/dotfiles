#!/usr/bin/env python3
# smart split kitten: enforce max splits, manage window sizing, and guide layout flow

"""
smart_split kitten entrypoint.

Primary responsibilities:
- Create controlled split layouts (max N panes per tab) with predictable placement.
- Optionally expand/shrink the OS window to preserve usable cell geometry.
- Normalize layout after close actions and apply the Hyprland repaint workaround.
"""

from __future__ import annotations

import os
import time

from kittens.tui.handler import result_handler
from kitty.fast_data_types import add_timer
from kitty.typing_compat import BossType

from smart_split_hyprland import split_repaint_focus_bounce
from smart_split_kitty import (
    active_tab,
    active_tab_manager,
    close_active_window,
    tab_window_ids,
    window_count,
)
from smart_split_layout import (
    active_window_is_square_slot,
    bottom_row_left_right,
    canonical_order_from_pairs,
    geometry_ready,
    group_ids_ready,
    layout_shape_matches,
    normalize_layout,
    order_by_geometry,
    order_matches_geometry,
    pane_sizes_ok,
    three_pane_layout_inverted,
)
from smart_split_state import (
    ensure_state,
    sync_window_order,
    wait_for_window_ids_change,
    wait_for_window_ids_settle,
)

WIDTH_DELTA_CELLS = 8
HEIGHT_DELTA_CELLS = 4
_OS_RESIZE_ENV = "KITTY_SMART_SPLIT_OS_RESIZE"


def main(args: list[str]) -> list[str]:
    # Parameters are handled in handle_result.
    return args


def _os_resize_enabled() -> bool:
    """
    Return True when OS window resizing is explicitly enabled.

    Resizing is opt-in to avoid compositor geometry artifacts on split/close.
    """
    setting = os.environ.get(_OS_RESIZE_ENV, "0").strip().lower()
    return setting in ("1", "true", "yes", "on")


def _ensure_order(
    tab,
    state: dict,
    current_ids: list[int] | None = None,
) -> list[int]:
    """
    Return a stable slot order for the current window ids.

    The order is stored in state and rebuilt when stale.
    """
    window_ids = current_ids if current_ids is not None else tab_window_ids(tab)
    order = state.get("order")
    if not isinstance(order, list):
        order = []
    if len(order) != len(window_ids) or set(order) != set(window_ids):
        # Prefer a stable creation order before falling back to geometry.
        order = sync_window_order(state, window_ids, previous_ids=window_ids)
        if len(order) != len(window_ids) or set(order) != set(window_ids):
            # Fall back to geometry ordering when ids cannot be reconciled.
            order = order_by_geometry(tab, window_ids)
    state["order"] = order
    return order


def _parse_args(args: list[str]) -> tuple[int, str, str]:
    """
    Parse kitten arguments while accounting for the injected kitten name.

    Kitty prepends the kitten identifier to the argument list, so parsing starts
    after the first element when it is not a numeric max window value.
    """
    max_windows = 4
    orientation = "auto"
    mode = "split"

    param_args = args
    if args and not args[0].lstrip("-").isdigit():
        param_args = args[1:]

    if param_args:
        try:
            max_windows = int(param_args[0])
        except Exception:
            pass
        if len(param_args) > 1 and param_args[1] in ("hsplit", "vsplit", "auto"):
            orientation = param_args[1]
        if len(param_args) > 2 and param_args[2] in (
            "split",
            "grow",
            "shrink",
            "close_window",
            "close_tab",
            "normalize",
        ):
            mode = param_args[2]

    return max_windows, orientation, mode


def _wait_for_group_ids(tab, window_ids: list[int]) -> None:
    """Wait briefly for window group ids to become available."""
    for _ in range(12):
        if group_ids_ready(tab, window_ids):
            return
        time.sleep(0.03)


def _schedule_normalize_after_close(
    boss: BossType,
    tab,
    state: dict,
    before_ids: list[int],
    os_window_id: int | None,
    order_after: list[int] | None,
    desired_focus_id: int | None,
) -> None:
    """
    Normalize the layout after a close once the window list has updated.

    The delay prevents the normalization step from racing kitty's close handling.
    """

    def do_normalize(_timer_id: int | None) -> None:
        after_ids = wait_for_window_ids_change(tab, before_ids)
        if order_after:
            expected_count = len(order_after)
            # Await the expected window count to avoid racing the close path.
            for _ in range(30):
                if len(after_ids) == expected_count:
                    break
                time.sleep(0.03)
                after_ids = tab_window_ids(tab)
        after_ids = wait_for_window_ids_settle(tab)
        _wait_for_group_ids(tab, after_ids)
        order: list[int] = []
        if order_after:
            order = [wid for wid in order_after if wid in after_ids]
        if len(order) != len(after_ids) or set(order) != set(after_ids):
            # Preserve the post-close rotation order when possible.
            order = [wid for wid in order if wid in after_ids]
            for wid in after_ids:
                if wid not in order:
                    order.append(wid)
        if len(order) != len(after_ids) or set(order) != set(after_ids):
            order = sync_window_order(state, after_ids, previous_ids=before_ids)
        # Apply the canonical layout to prevent stacked or nested splits.
        order = normalize_layout(tab, order)
        canonical_after = canonical_order_from_pairs(tab, after_ids)
        if canonical_after:
            # Keep state aligned with the canonical slot order after close.
            order = canonical_after
        if not layout_shape_matches(tab, len(after_ids)):
            # Retry once after the layout settles; prefer explicit rotation order over geometry.
            after_ids = wait_for_window_ids_settle(tab)
            _wait_for_group_ids(tab, after_ids)
            if order_after:
                # Preserve the intended post-close slot rotation during recovery.
                order = [wid for wid in order_after if wid in after_ids]
                for wid in after_ids:
                    if wid not in order:
                        order.append(wid)
            elif geometry_ready(tab, after_ids):
                order = order_by_geometry(tab, after_ids)
            else:
                order = sync_window_order(state, after_ids, previous_ids=before_ids)
            order = normalize_layout(tab, order)
            canonical_after = (
                canonical_order_from_pairs(tab, after_ids) or canonical_after
            )
            if canonical_after:
                order = canonical_after
        if len(after_ids) == 3 and three_pane_layout_inverted(tab, after_ids):
            # Correct the inverted 3-pane tree produced by a top-row close from 4 panes.
            recovery_order: list[int] = []
            if order_after:
                # Favor the rotation queue so the visual progression remains stable.
                recovery_order = [wid for wid in order_after if wid in after_ids]
                for wid in after_ids:
                    if wid not in recovery_order:
                        recovery_order.append(wid)
            elif canonical_after and len(canonical_after) == 3:
                recovery_order = canonical_after
            elif geometry_ready(tab, after_ids):
                recovery_order = order_by_geometry(tab, after_ids)
            else:
                recovery_order = sync_window_order(
                    state, after_ids, previous_ids=before_ids
                )
            for _ in range(3):
                order = normalize_layout(tab, recovery_order)
                canonical_after = (
                    canonical_order_from_pairs(tab, after_ids) or canonical_after
                )
                if canonical_after:
                    order = canonical_after
                if layout_shape_matches(tab, 3) and not three_pane_layout_inverted(
                    tab, after_ids
                ):
                    break
                time.sleep(0.03)
        left_right_order: list[int] | None = None
        if canonical_after:
            left_right_order = canonical_after
        elif geometry_ready(tab, after_ids):
            left_right_order = order_by_geometry(tab, after_ids)
        # Only force left/right when the layout is not already canonical.
        should_force_left_right = (
            len(after_ids) == 2
            and left_right_order
            and not layout_shape_matches(tab, 2)
        )
        if should_force_left_right:
            # Enforce a left/right split after close to avoid stacked panes.
            try:
                tab.set_active_window(left_right_order[0])
                boss.call_remote_control(
                    None,
                    ("action", "layout_action", "move_to_screen_edge", "left"),
                )
                try:
                    tab.reset_window_sizes()
                except Exception:
                    pass
                refreshed = canonical_order_from_pairs(tab, after_ids)
                if refreshed:
                    order = refreshed
                    canonical_after = refreshed
            except Exception:
                pass
        state["order"] = order
        if (
            _os_resize_enabled()
            and os_window_id is not None
            and state["expanded"]
            and len(after_ids) == 1
        ):
            try:
                boss.resize_os_window(
                    os_window_id,
                    width=-state["width_delta"],
                    height=-state["height_delta"],
                    unit="cells",
                    incremental=True,
                )
            except Exception:
                pass
            else:
                state["expanded"] = False
            # Re-apply sizing after the OS window resize to avoid stale geometry.
            order = normalize_layout(tab, order)
            state["order"] = order
        focus_id: int | None = None
        if len(after_ids) == 2:
            # When two panes remain, focus the right pane for a natural progression.
            if canonical_after and len(canonical_after) == 2:
                focus_id = canonical_after[1]
            elif geometry_ready(tab, after_ids):
                geometry_order = order_by_geometry(tab, after_ids)
                if len(geometry_order) == 2:
                    focus_id = geometry_order[1]
        elif desired_focus_id is not None and desired_focus_id in after_ids:
            focus_id = desired_focus_id
        if focus_id is not None:
            try:
                tab.set_active_window(focus_id)
            except Exception:
                pass
        # Hyprland/Wayland may skip repaint after close/resize; force a bounce.
        split_repaint_focus_bounce()

    add_timer(do_normalize, 0.06, False)


@result_handler(no_ui=True)
def handle_result(
    args: list[str], answer: object, target_window_id: int, boss: BossType
) -> None:
    max_windows, orientation, mode = _parse_args(args)

    tab = active_tab(boss)
    if tab is None:
        return

    tm = active_tab_manager(boss)
    os_window_id = getattr(tm, "os_window_id", None) if tm is not None else None
    current_ids = tab_window_ids(tab)
    current_window_count = len(current_ids) if current_ids else window_count(tab)

    state_key = os_window_id if os_window_id is not None else "__default__"
    state = ensure_state(boss, state_key, WIDTH_DELTA_CELLS, HEIGHT_DELTA_CELLS)
    if not _os_resize_enabled() and state["expanded"]:
        # Resizing may be disabled while a prior expansion flag is still set.
        state["expanded"] = False
    # Track rotation order based on creation; geometry is used only when stale.
    _ensure_order(tab, state, current_ids)

    if mode == "normalize":
        # Normalize after close operations have completed.
        stable_ids = wait_for_window_ids_settle(tab)
        order = sync_window_order(state, stable_ids)
        order = normalize_layout(tab, order)
        state["order"] = order
        return

    if mode in ("shrink", "close_window", "close_tab"):
        if mode == "close_window" and current_window_count <= 1:
            return
        if mode == "shrink":
            should_shrink = (
                _os_resize_enabled()
                and state["expanded"]
                and current_window_count <= 2
                and os_window_id is not None
            )
            if should_shrink:
                try:
                    boss.resize_os_window(
                        os_window_id,
                        width=-state["width_delta"],
                        height=-state["height_delta"],
                        unit="cells",
                        incremental=True,
                    )
                except Exception:
                    pass
                else:
                    state["expanded"] = False
                # Keep the layout sized to the resized OS window.
                order = sync_window_order(state, tab_window_ids(tab))
                order = normalize_layout(tab, order)
                state["order"] = order
            return
        if mode == "close_window":
            before_ids = tab_window_ids(tab)
            canonical_before = canonical_order_from_pairs(tab, before_ids)
            if canonical_before:
                # Use canonical layout order so close preserves slot rotation.
                order_before = canonical_before
            elif geometry_ready(tab, before_ids):
                # Fall back to geometry order when the layout tree is unstable.
                order_before = order_by_geometry(tab, before_ids)
            else:
                order_before = _ensure_order(tab, state, before_ids)
            desired_focus_id = None
            order_after: list[int] | None = None
            if len(before_ids) == 4:
                # Rotate 4→3 by row-major slot order to preserve the expected progression.
                slot_order = None
                if canonical_before and len(canonical_before) == 4:
                    slot_order = canonical_before
                elif geometry_ready(tab, before_ids):
                    slot_order = order_by_geometry(tab, before_ids)
                else:
                    slot_order = order_before
                if slot_order and target_window_id in slot_order:
                    order_before = slot_order
                    order_after = [wid for wid in slot_order if wid != target_window_id]
            if target_window_id in order_before and len(order_before) > 1:
                # Focus the next slot in rotation order after the closed window.
                closed_index = order_before.index(target_window_id)
                if desired_focus_id is None:
                    desired_focus_id = order_before[
                        (closed_index + 1) % len(order_before)
                    ]
            # Preserve rotation order by removing the closed id from the slot list.
            if order_after is None:
                order_after = [wid for wid in order_before if wid != target_window_id]
            close_active_window(boss, target_window_id)
            _schedule_normalize_after_close(
                boss,
                tab,
                state,
                before_ids,
                os_window_id,
                order_after,
                desired_focus_id,
            )
        elif mode == "close_tab":
            try:
                boss.close_tab()
            finally:
                state["expanded"] = False
        return

    if mode not in ("split", "grow"):
        return

    if current_window_count >= max_windows:
        return

    if current_window_count == 3:
        # Restrict 3-pane splits to the bottom slot to avoid square splits.
        active_window = getattr(tab, "active_window", None)
        active_window_id = getattr(active_window, "id", None)
        geometry_order = order_by_geometry(tab, current_ids)
        if (
            active_window_id is None
            or len(geometry_order) != 3
            or active_window_id != geometry_order[2]
        ):
            return

    if active_window_is_square_slot(tab):
        # Prevent splitting panes that already occupy a square slot.
        return

    try:
        boss.call_remote_control(None, ("goto-layout", "splits"))
    except Exception:
        pass

    chosen = orientation if orientation != "auto" else "vsplit"
    move_bottom = False

    if orientation == "auto":
        if current_window_count == 1:
            chosen = "vsplit"  # first split: left/right
        elif current_window_count == 2:
            # Create a third pane, then move it to the bottom edge.
            chosen = "hsplit"
            move_bottom = True
        elif current_window_count == 3:
            chosen = "vsplit"
        else:
            chosen = "vsplit" if current_window_count % 2 == 0 else "hsplit"

    if (
        _os_resize_enabled()
        and current_window_count == 1
        and os_window_id is not None
        and not state["expanded"]
    ):
        try:
            boss.resize_os_window(
                os_window_id,
                width=state["width_delta"],
                height=state["height_delta"],
                unit="cells",
                incremental=True,
            )
        except Exception:
            pass
        else:
            state["expanded"] = True

    before_ids = tab_window_ids(tab)
    # Capture the pre-split order so the rotation queue remains stable.
    order_before = _ensure_order(tab, state, before_ids)
    launch_args = ["--cwd=current", f"--location={chosen}"]
    if current_window_count >= 1:
        launch_args.append("--env=KITTY_SUPPRESS_BANNER=1")
    boss.launch(*launch_args)

    after_ids = wait_for_window_ids_change(tab, before_ids)
    if move_bottom:
        new_ids_for_move = [wid for wid in after_ids if wid not in before_ids]
        if len(new_ids_for_move) != 1:
            # If the new pane has not appeared yet, wait for the list to settle.
            after_ids = wait_for_window_ids_settle(tab)
            new_ids_for_move = [wid for wid in after_ids if wid not in before_ids]
        if len(new_ids_for_move) == 1:
            try:
                # Move the newly created pane into the bottom slot for 3-pane layouts.
                tab.set_active_window(new_ids_for_move[0])
                boss.call_remote_control(
                    None,
                    ("action", "layout_action", "move_to_screen_edge", "bottom"),
                )
            except Exception:
                pass
    after_ids = wait_for_window_ids_settle(tab)
    new_ids = [wid for wid in after_ids if wid not in before_ids]
    order = []
    if len(new_ids) == 1:
        new_id = new_ids[0]
        if current_window_count in (1, 2):
            # Append new panes as the next slot in the rotation order.
            order = [wid for wid in order_before if wid in before_ids] + [new_id]
        elif current_window_count == 3 and len(order_before) == 3:
            bottom_id = order_before[2]
            left_right = bottom_row_left_right(tab, bottom_id, new_id)
            if left_right is not None:
                # Slot order is row-major: top-left, top-right, bottom-left, bottom-right.
                left_id, right_id = left_right
                order = [order_before[0], order_before[1], left_id, right_id]
    if len(order) != len(after_ids) or set(order) != set(after_ids):
        order = sync_window_order(
            state, after_ids, new_ids=new_ids, previous_ids=before_ids
        )
    # Normalize when the layout shape or slot ordering is off; avoid extra work otherwise.
    layout_ok = layout_shape_matches(tab, len(after_ids))
    geometry_ok = geometry_ready(tab, order) and order_matches_geometry(tab, order)
    # Enforce minimum pane sizes to prevent tiny panes from lingering.
    size_ok = pane_sizes_ok(tab, after_ids)
    if not layout_ok or not geometry_ok or not size_ok:
        _wait_for_group_ids(tab, after_ids)
        order = normalize_layout(tab, order)
        canonical_after = canonical_order_from_pairs(tab, after_ids)
        if canonical_after:
            # Refresh state with the canonical slot order post-normalization.
            order = canonical_after
    else:
        try:
            tab.reset_window_sizes()
        except Exception:
            pass
    state["order"] = order

    # Force an immediate repaint after split creation on Hyprland/Wayland.
    split_repaint_focus_bounce()
