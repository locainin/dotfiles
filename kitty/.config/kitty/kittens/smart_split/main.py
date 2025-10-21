#!/usr/bin/env python3
# smart split kitten: enforce max splits, manage window sizing, and guide layout flow

from __future__ import annotations

from kittens.tui.handler import result_handler
from kitty.typing_compat import BossType

WIDTH_DELTA_CELLS = 8
HEIGHT_DELTA_CELLS = 4


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
