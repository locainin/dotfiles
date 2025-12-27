"""
Layout enforcement and square-slot detection for the smart_split kitten.

This module normalizes the splits tree into approved shapes and detects when the
active pane already has both horizontal and vertical adjacency.
"""

from __future__ import annotations

import os

from kitty.layout.base import lgd

from smart_split_kitty import active_window_neighbors, window_group_id

_MIN_COLS_ENV = "KITTY_SMART_SPLIT_MIN_COLS"
_MIN_ROWS_ENV = "KITTY_SMART_SPLIT_MIN_ROWS"
_DEFAULT_MIN_COLS = 10
_DEFAULT_MIN_ROWS = 3

try:
    from kitty.layout.splits import Pair
except Exception:  # pragma: no cover - kitty layout internals can vary by version.
    Pair = None


def _reset_window_sizes(tab) -> None:
    """Reset window sizes to the layout defaults, ignoring failures."""
    try:
        tab.reset_window_sizes()
    except Exception:
        return


def _apply_pairs_root(tab, pairs_root) -> bool:
    """
    Replace the splits pairs root directly and relayout the tab.

    Direct assignment avoids layout.unserialize side effects that can reorder groups.
    """
    layout = getattr(tab, "current_layout", None)
    if layout is None or layout.__class__.__name__ != "Splits":
        return False
    try:
        layout.pairs_root = pairs_root
        tab.relayout()
    except Exception:
        return False
    return True


def _build_pairs_root(group_ids: list[int]) -> object | None:
    """Build a splits Pair tree for canonical layouts based on group ids."""
    if Pair is None:
        return None
    count = len(group_ids)
    if count == 2:
        root = Pair(horizontal=True)
        root.one = group_ids[0]
        root.two = group_ids[1]
        return root
    if count == 3:
        root = Pair(horizontal=False)
        top = Pair(horizontal=True)
        top.one = group_ids[0]
        top.two = group_ids[1]
        root.one = top
        root.two = group_ids[2]
        return root
    if count == 4:
        root = Pair(horizontal=False)
        top = Pair(horizontal=True)
        top.one = group_ids[0]
        top.two = group_ids[1]
        bottom = Pair(horizontal=True)
        bottom.one = group_ids[2]
        bottom.two = group_ids[3]
        root.one = top
        root.two = bottom
        return root
    return None


def _layout_pairs(tab) -> dict | None:
    """Return the serialized layout pairs for splits, or None if unavailable."""
    layout = getattr(tab, "current_layout", None)
    if layout is None or layout.__class__.__name__ != "Splits":
        return None
    try:
        state = layout.serialize(tab.windows)
    except Exception:
        return None
    return state.get("pairs")


def _collect_pair_leaves(node: object) -> list[int]:
    """Return all leaf ids from a serialized pairs tree."""
    if isinstance(node, dict):
        leaves: list[int] = []
        leaves.extend(_collect_pair_leaves(node.get("one")))
        leaves.extend(_collect_pair_leaves(node.get("two")))
        return leaves
    if isinstance(node, int):
        return [node]
    return []


def layout_shape_matches(tab, count: int) -> bool:
    """
    Return True when the serialized splits tree matches the canonical shape.

    Canonical shapes:
    - 1 pane: single
    - 2 panes: left/right
    - 3 panes: two panes on top, one full-width on bottom
    - 4 panes: 2x2 grid
    """
    if count <= 1:
        return True
    pairs = _layout_pairs(tab)
    if not isinstance(pairs, dict):
        return False
    leaves = _collect_pair_leaves(pairs)
    if len(leaves) != count:
        return False

    def is_pair(node: object) -> bool:
        return isinstance(node, dict)

    def is_leaf(node: object) -> bool:
        return isinstance(node, int)

    def horizontal_flag(node: dict) -> bool:
        return node.get("horizontal", True)

    if count == 2:
        return (
            horizontal_flag(pairs)
            and is_leaf(pairs.get("one"))
            and is_leaf(pairs.get("two"))
        )

    if count == 3:
        return (
            not horizontal_flag(pairs)
            and is_pair(pairs.get("one"))
            and is_leaf(pairs.get("two"))
            and horizontal_flag(pairs["one"])
            and is_leaf(pairs["one"].get("one"))
            and is_leaf(pairs["one"].get("two"))
        )

    if count == 4:
        return (
            not horizontal_flag(pairs)
            and is_pair(pairs.get("one"))
            and is_pair(pairs.get("two"))
            and horizontal_flag(pairs["one"])
            and horizontal_flag(pairs["two"])
            and is_leaf(pairs["one"].get("one"))
            and is_leaf(pairs["one"].get("two"))
            and is_leaf(pairs["two"].get("one"))
            and is_leaf(pairs["two"].get("two"))
        )

    return False


def group_ids_ready(tab, window_ids: list[int]) -> bool:
    """Return True when all window group ids are available."""
    for wid in window_ids:
        if window_group_id(tab, wid) is None:
            return False
    return True


def canonical_order_from_pairs(tab, window_ids: list[int]) -> list[int] | None:
    """
    Return the canonical order from the current splits layout pairs.

    This decodes the serialized pairs tree into the expected slot order:
    - 2 panes: left, right
    - 3 panes: top-left, top-right, bottom
    - 4 panes: top-left, top-right, bottom-left, bottom-right
    """
    count = len(window_ids)
    if count < 2 or count > 4:
        return None
    pairs = _layout_pairs(tab)
    if not isinstance(pairs, dict):
        return None
    if not layout_shape_matches(tab, count):
        return None

    group_to_window: dict[int, int] = {}
    for wid in window_ids:
        gid = window_group_id(tab, wid)
        if gid is None:
            return None
        group_to_window[gid] = wid

    def map_gid(gid: int | None) -> int | None:
        if gid is None:
            return None
        return group_to_window.get(gid)

    if count == 2:
        left = map_gid(pairs.get("one"))
        right = map_gid(pairs.get("two"))
        if left is None or right is None:
            return None
        return [left, right]

    if count == 3:
        top = pairs.get("one")
        bottom_gid = map_gid(pairs.get("two"))
        if not isinstance(top, dict) or bottom_gid is None:
            return None
        top_left = map_gid(top.get("one"))
        top_right = map_gid(top.get("two"))
        if top_left is None or top_right is None:
            return None
        return [top_left, top_right, bottom_gid]

    top = pairs.get("one")
    bottom = pairs.get("two")
    if not isinstance(top, dict) or not isinstance(bottom, dict):
        return None
    top_left = map_gid(top.get("one"))
    top_right = map_gid(top.get("two"))
    bottom_left = map_gid(bottom.get("one"))
    bottom_right = map_gid(bottom.get("two"))
    if (
        top_left is None
        or top_right is None
        or bottom_left is None
        or bottom_right is None
    ):
        return None
    return [top_left, top_right, bottom_left, bottom_right]


def _pairs_has_both_axes(
    pairs: object,
    target_gid: int,
    has_horizontal: bool,
    has_vertical: bool,
) -> bool:
    """
    Walk the layout pairs tree and track whether both split orientations exist.

    A leaf is considered square when its path includes a left/right split and a
    top/bottom split in any order.
    """
    if isinstance(pairs, dict):
        # "horizontal" defaults to True when absent in the serialized layout.
        horizontal = pairs.get("horizontal", True)
        next_has_horizontal = has_horizontal or horizontal
        next_has_vertical = has_vertical or not horizontal
        return _pairs_has_both_axes(
            pairs.get("one"), target_gid, next_has_horizontal, next_has_vertical
        ) or _pairs_has_both_axes(
            pairs.get("two"), target_gid, next_has_horizontal, next_has_vertical
        )
    return pairs == target_gid and has_horizontal and has_vertical


def _neighbor_present(value: object) -> bool:
    if isinstance(value, list):
        return bool(value)
    return value is not None


def _neighbors_have_both_axes(neighbors: dict) -> bool:
    """Return True when neighbor metadata indicates both axes are occupied."""
    horizontal = _neighbor_present(neighbors.get("left")) or _neighbor_present(
        neighbors.get("right")
    )
    vertical = _neighbor_present(neighbors.get("top")) or _neighbor_present(
        neighbors.get("bottom")
    )
    return horizontal and vertical


def _window_geometry(tab, window_id: int):
    """
    Return the window geometry for a given window id.

    Geometry is read from the window object and can be unavailable during relayout.
    """
    try:
        window = tab.windows.id_map.get(window_id)
        if window is None:
            return None
        return getattr(window, "geometry", None)
    except Exception:
        return None


def _geometry_valid(geom) -> bool:
    """Return True when geometry has non-zero width and height."""
    try:
        return (geom.right - geom.left) > 0 and (geom.bottom - geom.top) > 0
    except Exception:
        return False


def _center_y(geom) -> float:
    """Return the vertical center of a geometry rectangle."""
    return (geom.top + geom.bottom) / 2.0


def _stable_index_map(order: list[int]) -> dict[int, int]:
    """Return a stable index map used as a tie-breaker in geometry sorting."""
    return {wid: idx for idx, wid in enumerate(order)}


def _reorder_by_geometry(tab, order: list[int]) -> list[int]:
    """
    Return a geometry-based ordering to keep normalized layouts predictable.

    Geometry sorting preserves slot ordering for rotation-based layouts.
    Stable order is used as a tie-breaker.
    """
    count = len(order)
    if count < 2 or count > 4:
        return order

    geometry_map = {}
    for wid in order:
        geom = _window_geometry(tab, wid)
        if geom is None or not _geometry_valid(geom):
            return order
        geometry_map[wid] = geom

    stable_index = _stable_index_map(order)
    epsilon = 0.1

    if count == 2:
        left_values = {wid: geometry_map[wid].left for wid in order}
        if len(set(left_values.values())) == 1:
            return order
        return sorted(order, key=lambda wid: (left_values[wid], stable_index[wid]))

    if count == 3:
        center_y_map = {wid: _center_y(geometry_map[wid]) for wid in order}
        max_center_y = max(center_y_map.values())
        bottom_candidates = [
            wid for wid in order if abs(center_y_map[wid] - max_center_y) <= epsilon
        ]
        bottom = min(
            bottom_candidates,
            key=lambda wid: (geometry_map[wid].left, stable_index[wid]),
        )
        top = [wid for wid in order if wid != bottom]
        if len(top) != 2:
            return order
        top_sorted = sorted(
            top, key=lambda wid: (geometry_map[wid].left, stable_index[wid])
        )
        return top_sorted + [bottom]

    sorted_by_y = sorted(
        order, key=lambda wid: (_center_y(geometry_map[wid]), stable_index[wid])
    )
    top = sorted_by_y[:2]
    bottom = sorted_by_y[2:]
    top_sorted = sorted(
        top, key=lambda wid: (geometry_map[wid].left, stable_index[wid])
    )
    bottom_sorted = sorted(
        bottom, key=lambda wid: (geometry_map[wid].left, stable_index[wid])
    )
    return top_sorted + bottom_sorted


def order_by_geometry(tab, order: list[int]) -> list[int]:
    """
    Return the geometry-based order without modifying the layout.

    This is used to keep the window order aligned with on-screen positions.
    """
    return _reorder_by_geometry(tab, order)


def geometry_ready(tab, order: list[int]) -> bool:
    """Return True when all window geometries are available and non-zero."""
    for wid in order:
        geom = _window_geometry(tab, wid)
        if geom is None or not _geometry_valid(geom):
            return False
    return True


def order_matches_geometry(tab, order: list[int]) -> bool:
    """
    Return True when the geometry-based order matches the provided order.

    False is returned when geometry is unavailable.
    """
    if not geometry_ready(tab, order):
        return False
    geometry_order = order_by_geometry(tab, order)
    if len(geometry_order) != len(order) or set(geometry_order) != set(order):
        return False
    return geometry_order == order


def three_pane_layout_inverted(tab, window_ids: list[int]) -> bool:
    """
    Return True when a 3-pane layout is inverted (top full-width, bottom split).

    This guards against the common close path where the splits tree collapses into
    a top leaf and a bottom pair, which is visually inconsistent with the intended
    top-row split + bottom full-width layout.
    """
    if len(window_ids) != 3:
        return False
    pairs = _layout_pairs(tab)
    if isinstance(pairs, dict):

        def is_pair(node: object) -> bool:
            return isinstance(node, dict)

        def is_leaf(node: object) -> bool:
            return isinstance(node, int)

        if not pairs.get("horizontal", True):
            top_node = pairs.get("one")
            bottom_node = pairs.get("two")
            if (
                is_leaf(top_node)
                and is_pair(bottom_node)
                and bottom_node.get("horizontal", True)
                and is_leaf(bottom_node.get("one"))
                and is_leaf(bottom_node.get("two"))
            ):
                return True
            return False
    if not geometry_ready(tab, window_ids):
        return False
    geometry_map: dict[int, object] = {}
    for wid in window_ids:
        geom = _window_geometry(tab, wid)
        if geom is None or not _geometry_valid(geom):
            return False
        geometry_map[wid] = geom
    top_values = {wid: geometry_map[wid].top for wid in window_ids}
    min_top = min(top_values.values())
    max_top = max(top_values.values())
    # Allow slight coordinate drift due to borders and rounding.
    epsilon = max(1, lgd.cell_height // 2)
    top_row = [wid for wid in window_ids if abs(top_values[wid] - min_top) <= epsilon]
    bottom_row = [
        wid for wid in window_ids if abs(top_values[wid] - max_top) <= epsilon
    ]
    if len(top_row) != 1 or len(bottom_row) != 2:
        return False
    total_width = max(geometry_map[wid].right for wid in window_ids) - min(
        geometry_map[wid].left for wid in window_ids
    )
    top_width = geometry_map[top_row[0]].right - geometry_map[top_row[0]].left
    # Confirm the single top pane spans nearly the full width before treating as inverted.
    return top_width >= int(total_width * 0.9)


def _read_min_env(name: str, default: int) -> int:
    """Return a validated integer from the environment or the provided default."""
    value = os.environ.get(name)
    if not value:
        return default
    try:
        parsed = int(value)
    except Exception:
        return default
    return parsed if parsed > 0 else default


def pane_sizes_ok(
    tab, window_ids: list[int], min_cols: int = 10, min_rows: int = 3
) -> bool:
    """
    Return True when each pane meets the minimum cell size threshold.

    Environment overrides:
    - KITTY_SMART_SPLIT_MIN_COLS
    - KITTY_SMART_SPLIT_MIN_ROWS

    Geometry that is unavailable or invalid does not trigger a failure.
    """
    if not window_ids:
        return True
    min_cols = _read_min_env(_MIN_COLS_ENV, min_cols or _DEFAULT_MIN_COLS)
    min_rows = _read_min_env(_MIN_ROWS_ENV, min_rows or _DEFAULT_MIN_ROWS)
    if not geometry_ready(tab, window_ids):
        return True
    cell_width = max(1, getattr(lgd, "cell_width", 1))
    cell_height = max(1, getattr(lgd, "cell_height", 1))
    for wid in window_ids:
        geom = _window_geometry(tab, wid)
        if geom is None or not _geometry_valid(geom):
            return True
        cols = max(1, (geom.right - geom.left) // cell_width)
        rows = max(1, (geom.bottom - geom.top) // cell_height)
        if cols < min_cols or rows < min_rows:
            return False
    return True


def bottom_row_left_right(tab, first_id: int, second_id: int) -> tuple[int, int] | None:
    """
    Return the bottom row ids in left/right order using geometry.

    None is returned when geometry is unavailable or indistinguishable.
    """
    first_geom = _window_geometry(tab, first_id)
    second_geom = _window_geometry(tab, second_id)
    if first_geom is None or second_geom is None:
        return None
    if not _geometry_valid(first_geom) or not _geometry_valid(second_geom):
        return None
    if first_geom.left == second_geom.left:
        return None
    if first_geom.left > second_geom.left:
        return (second_id, first_id)
    return (first_id, second_id)


def active_window_is_square_slot(tab) -> bool:
    """
    Return True when the active window already has both axes of adjacency.

    The layout tree is preferred for detection, with neighbor metadata as a fallback.
    """
    active_window = getattr(tab, "active_window", None)
    active_window_id = getattr(active_window, "id", None)
    if active_window_id is None:
        return False

    layout = getattr(tab, "current_layout", None)
    if layout is not None and layout.__class__.__name__ == "Splits":
        try:
            # Prefer the layout-provided neighbor map for accurate adjacency.
            neighbors = layout.neighbors_for_window(active_window, tab.windows)
            if _neighbors_have_both_axes(neighbors):
                return True
        except Exception:
            pass

    group_id = window_group_id(tab, active_window_id)
    if group_id is None:
        return False
    pairs = _layout_pairs(tab)
    if pairs is not None and _pairs_has_both_axes(pairs, group_id, False, False):
        return True
    neighbors = active_window_neighbors(tab)
    if neighbors:
        return _neighbors_have_both_axes(neighbors)
    return False


def normalize_layout(tab, order: list[int]) -> list[int]:
    """
    Normalize the splits layout to supported shapes based on window count.

    Supported shapes:
    - 1 pane: single
    - 2 panes: left/right columns
    - 3 panes: two panes on top, one full-width on bottom
    - 4 panes: 2x2 grid (row-major order)

    The returned order reflects any geometry-based reordering applied.
    """
    count = len(order)
    if count <= 1:
        _reset_window_sizes(tab)
        return order
    if count > 4:
        return order
    layout = getattr(tab, "current_layout", None)
    if layout is None or layout.__class__.__name__ != "Splits":
        return order

    group_ids: list[int] = []
    for wid in order:
        gid = window_group_id(tab, wid)
        if gid is not None:
            group_ids.append(gid)
    if len(group_ids) != count:
        return order

    pairs_root = _build_pairs_root(group_ids)
    if pairs_root is not None and _apply_pairs_root(tab, pairs_root):
        _reset_window_sizes(tab)
        return order

    if count == 2:
        pairs = {
            "horizontal": True,
            "one": group_ids[0],
            "two": group_ids[1],
        }
    elif count == 3:
        pairs = {
            "horizontal": False,
            "one": {
                "horizontal": True,
                "one": group_ids[0],
                "two": group_ids[1],
            },
            "two": group_ids[2],
        }
    else:
        pairs = {
            "horizontal": False,
            "one": {
                "horizontal": True,
                "one": group_ids[0],
                "two": group_ids[1],
            },
            "two": {
                "horizontal": True,
                "one": group_ids[2],
                "two": group_ids[3],
            },
        }

    try:
        state = layout.serialize(tab.windows)
        state["pairs"] = pairs
        layout.unserialize(state, tab.windows)
    except Exception:
        return order
    _reset_window_sizes(tab)
    return order
