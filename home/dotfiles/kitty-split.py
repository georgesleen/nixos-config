"""Kitten that splits a pane, treating an editor and its hx-sidebar as one pane."""

from kittens.tui.handler import result_handler


def main(args):
    pass


def regroup(pair, sidebar, editor, new, horizontal):
    """Rebuild pair so that the sidebar and editor sit together, split from new.

    All window arguments are group ids. pair holds sidebar and, on its other
    side, a pair of editor and new. Any other shape is left unchanged.
    """
    other = pair.two if pair.one == sidebar else pair.one
    if not isinstance(other, type(pair)) or {other.one, other.two} != {editor, new}:
        return
    side = type(pair)(horizontal=pair.horizontal)
    side.one, side.two = (sidebar, editor) if pair.one == sidebar else (editor, sidebar)
    share = pair.bias if pair.one == sidebar else 1 - pair.bias
    side.set_bias(sidebar, round(share * (200 if pair.horizontal == horizontal else 100)))
    pair.horizontal, pair.bias = horizontal, 0.5
    pair.one, pair.two = side, new


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    from kitty.launch import launch, parse_launch_args

    location = args[1]
    tab = boss.active_tab
    active = tab.active_window if tab else None
    if active is None:
        return
    editor_id = int(active.user_vars.get("hx_sidebar", active.id))
    spec = parse_launch_args(
        [f"--location={location}", "--bias=50", "--cwd=current", f"--next-to=id:{editor_id}"]
    )
    new = launch(boss, spec.opts, spec.args)
    sidebar = next((w for w in tab if w.user_vars.get("hx_sidebar") == str(editor_id)), None)
    editor = boss.window_id_map.get(editor_id)
    layout = tab.current_layout
    if None in (new, sidebar, editor) or layout.name != "splits":
        return
    group = tab.windows.group_for_window
    regroup(
        layout.pairs_root.pair_for_window(group(sidebar).id),
        group(sidebar).id,
        group(editor).id,
        group(new).id,
        location == "vsplit",
    )
    tab.relayout()
