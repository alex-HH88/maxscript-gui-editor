"""
MAXScript .ms file writer — round-trip safe.

Reconstructs the .ms file from a ParsedMS object:
  - pre_rollout  → verbatim
  - rollout block → regenerated control declarations + original event bodies
  - post_rollout → verbatim

Only control DECLARATION lines change.
Event handler DO-bodies are written back exactly as read.
Everything outside the rollout block is untouched.
"""
from __future__ import annotations
from .ms_parser import ParsedMS
from .code_generator import _q, _build_control_decl_only


def _build_rollout_header(parsed: ParsedMS) -> str:
    m = parsed.model
    ind = parsed.rollout_indent
    params = [_q(m.rollout_title)]
    if m.use_pos:
        params.append(f"pos:[{m.pos_x},{m.pos_y}]")
    if m.use_height:
        params.append(f"height:{m.height}")
    return f"{ind}rollout {m.rollout_name} {' '.join(params)}\n{ind}(\n"


def write_ms_file(parsed: ParsedMS, path: str) -> None:
    """
    Write the round-trip .ms file.
    Control DECLARATIONS are regenerated from the model.
    Event handler DO-bodies are taken verbatim from parsed.event_bodies.
    Everything outside the rollout block is written unchanged.
    """
    ind = parsed.rollout_indent + "\t"
    lines: list[str] = []

    # --- pre_rollout verbatim ---
    lines.append(parsed.pre_rollout)

    # --- rollout header ---
    lines.append(_build_rollout_header(parsed))

    # --- controls ---
    for ctrl in parsed.model.controls:
        # declaration only (no event handlers — those follow separately)
        decl = _build_control_decl_only(ctrl, indent=ind)
        lines.append(decl + "\n")

        # event handler blocks — body verbatim from original
        for eh in ctrl.event_handlers:
            args_part = f" {eh.args}" if eh.args.strip() else ""
            lines.append(f"{ind}on {ctrl.name} {eh.event}{args_part} do\n")
            body = parsed.event_bodies.get((ctrl.name, eh.event), eh.code)
            # body is the raw text that was after "do" in the original file
            # it may or may not start with "(" on its own line
            if not body.endswith('\n'):
                body += '\n'
            lines.append(body)

    # --- extra lines (comments, locals) ---
    for _, raw in parsed.extra_lines:
        lines.append(raw)

    # --- close rollout ---
    lines.append(f"{parsed.rollout_indent})\n")

    # --- post_rollout verbatim ---
    lines.append(parsed.post_rollout)

    with open(path, 'w', encoding='utf-8') as f:
        f.write(''.join(lines))
