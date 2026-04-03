"""
MAXScript .ms file writer — round-trip safe, multi-rollout.

Iterates over ParsedMS.segments:
  TextSegment    → written verbatim
  RolloutSegment → header + control declarations regenerated from model,
                   event handler DO-bodies written verbatim from event_bodies
"""
from __future__ import annotations
from .ms_parser import ParsedMS, TextSegment, RolloutSegment
from .code_generator import _q, _build_control_decl_only


def _write_rollout_segment(seg: RolloutSegment) -> str:
    m = seg.model
    ind = seg.rollout_indent
    body_ind = ind + "\t"
    lines: list[str] = []

    # header
    params = [_q(m.rollout_title)]
    if m.use_pos:
        params.append(f"pos:[{m.pos_x},{m.pos_y}]")
    if m.use_height:
        params.append(f"height:{m.height}")
    lines.append(f"{ind}rollout {m.rollout_name} {' '.join(params)}\n")
    lines.append(f"{ind}(\n")

    # controls + their event handlers
    for ctrl in m.controls:
        lines.append(_build_control_decl_only(ctrl, indent=body_ind) + "\n")
        for eh in ctrl.event_handlers:
            args_part = f" {eh.args}" if eh.args.strip() else ""
            lines.append(f"{body_ind}on {ctrl.name} {eh.event}{args_part} do\n")
            body = seg.event_bodies.get((ctrl.name, eh.event), eh.code)
            if not body.endswith('\n'):
                body += '\n'
            lines.append(body)

    # orphaned event handlers (no matching control) — verbatim
    for raw in seg.orphaned_events:
        if not raw.endswith('\n'):
            raw += '\n'
        lines.append(raw)

    # extra lines (comments, locals)
    for raw in seg.extra_lines:
        lines.append(raw)

    # close rollout
    lines.append(f"{ind})\n")

    return ''.join(lines)


def write_ms_file(parsed: ParsedMS, path: str) -> None:
    parts: list[str] = []
    for seg in parsed.segments:
        if isinstance(seg, TextSegment):
            parts.append(seg.text)
        elif isinstance(seg, RolloutSegment):
            parts.append(_write_rollout_segment(seg))

    with open(path, 'w', encoding='utf-8') as f:
        f.write(''.join(parts))
