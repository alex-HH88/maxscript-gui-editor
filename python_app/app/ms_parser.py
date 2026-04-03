"""
MAXScript .ms file parser — round-trip safe, multi-rollout.

The file is split into alternating segments:
  TextSegment    — verbatim text (globals, functions, macroScript wrapper, …)
  RolloutSegment — one parsed rollout block (controls editable, event bodies preserved)

When writing back, TextSegments are reproduced verbatim and RolloutSegments
are regenerated from their models.  Event handler DO-bodies are always taken
from the original source, so logic code is never touched.
"""
from __future__ import annotations
import re
from dataclasses import dataclass, field
from typing import Union

from .models import RolloutModel, ControlModel, EventHandler, CONTROL_TYPES


# ---------------------------------------------------------------------------
# Segment types
# ---------------------------------------------------------------------------
@dataclass
class TextSegment:
    text: str


@dataclass
class RolloutSegment:
    model: RolloutModel
    rollout_indent: str = ""
    # Raw event-handler bodies: (ctrl_name, event) -> raw code string
    event_bodies: dict[tuple[str, str], str] = field(default_factory=dict)
    # Non-control, non-event lines inside the rollout body (comments, locals)
    extra_lines: list[str] = field(default_factory=list)
    parse_warnings: list[str] = field(default_factory=list)


# Top-level parsed file
@dataclass
class ParsedMS:
    segments: list[Union[TextSegment, RolloutSegment]] = field(default_factory=list)
    parse_warnings: list[str] = field(default_factory=list)

    @property
    def rollout_segments(self) -> list[RolloutSegment]:
        return [s for s in self.segments if isinstance(s, RolloutSegment)]

    def get_rollout(self, name: str) -> RolloutSegment | None:
        for s in self.rollout_segments:
            if s.model.rollout_name == name:
                return s
        return None


# ---------------------------------------------------------------------------
# Low-level helpers
# ---------------------------------------------------------------------------
_CTRL_TYPE_RE = re.compile(
    r'^\s*(' + '|'.join(re.escape(t) for t in CONTROL_TYPES) + r')\s+(\w+)(.*)',
    re.IGNORECASE
)
_ROLLOUT_RE = re.compile(
    r'^(\s*)rollout\s+(\w+)\s+"([^"]*)"(.*)',
    re.IGNORECASE
)
_ON_RE = re.compile(
    r'^\s*on\s+(\w+)\s+(\w+)(.*?)\s+do\s*$',
    re.IGNORECASE
)


def _unquote(s: str) -> str:
    s = s.strip()
    if s.startswith('"') and s.endswith('"'):
        return s[1:-1].replace('\\"', '"')
    return s


def _parse_array(s: str) -> list[str]:
    m = re.match(r'#\((.*)\)', s.strip(), re.DOTALL)
    if not m:
        return []
    inner = m.group(1)
    items = []
    for part in re.split(r',(?=(?:[^"]*"[^"]*")*[^"]*$)', inner):
        items.append(_unquote(part.strip()))
    return [i for i in items if i]


def _parse_vec2(s: str) -> tuple[float, float]:
    m = re.match(r'\[([^,\]]+),([^\]]+)\]', s.strip())
    if m:
        try:
            return float(m.group(1)), float(m.group(2))
        except ValueError:
            pass
    return 0.0, 0.0


def _parse_vec3(s: str) -> tuple[float, float, float]:
    m = re.match(r'\[([^,\]]+),([^,\]]+),([^\]]+)\]', s.strip())
    if m:
        try:
            return float(m.group(1)), float(m.group(2)), float(m.group(3))
        except ValueError:
            pass
    return 0.0, 100.0, 0.0


def _consume_value(s: str) -> tuple[str, str]:
    if not s:
        return '', ''
    if s[0] == '"':
        end = 1
        while end < len(s):
            if s[end] == '\\':
                end += 2
                continue
            if s[end] == '"':
                end += 1
                break
            end += 1
        return s[:end], s[end:].lstrip()
    if s.startswith('#('):
        depth = 0
        for i, c in enumerate(s):
            if c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
                if depth == 0:
                    return s[:i+1], s[i+1:].lstrip()
        return s, ''
    if s.startswith('#'):
        m = re.match(r'(#\w+)', s)
        if m:
            return m.group(1), s[m.end():].lstrip()
    if s[0] == '[':
        end = s.index(']') + 1 if ']' in s else len(s)
        return s[:end], s[end:].lstrip()
    m = re.match(r'([^\s:,]+)', s)
    if m:
        return m.group(1), s[m.end():].lstrip()
    return s, ''


def _parse_params(param_str: str) -> dict[str, str]:
    result: dict[str, str] = {}
    s = param_str.strip()
    while s:
        km = re.match(r'(\w+)\s*:', s)
        if not km:
            break
        key = km.group(1).lower()
        s = s[km.end():].lstrip()
        val, s = _consume_value(s)
        result[key] = val.strip()
    return result


def _apply_params(ctrl: ControlModel, params: dict[str, str]) -> None:
    for key, val in params.items():
        vl = val.lower()
        if key == 'pos':
            x, y = _parse_vec2(val)
            ctrl.x, ctrl.y = int(x), int(y)
            ctrl.use_pos = True
        elif key == 'width':
            try:
                ctrl.width = int(float(val)); ctrl.use_width = True
            except ValueError:
                pass
        elif key == 'height':
            try:
                ctrl.height = int(float(val)); ctrl.use_height = True
            except ValueError:
                pass
        elif key == 'offset':
            ox, oy = _parse_vec2(val)
            ctrl.offset_x, ctrl.offset_y = int(ox), int(oy)
            ctrl.use_offset = True
        elif key == 'across':
            try:
                ctrl.across = int(val)
            except ValueError:
                pass
        elif key == 'align':
            ctrl.align = val.lstrip('#').lower()
        elif key == 'enabled':
            ctrl.enabled = vl != 'false'
        elif key == 'visible':
            ctrl.visible = vl != 'false'
        elif key == 'tooltip':
            ctrl.tooltip = _unquote(val)
        elif key == 'range':
            lo, hi, v = _parse_vec3(val)
            ctrl.range_min, ctrl.range_max, ctrl.range_val = lo, hi, v
        elif key == 'type':
            ctrl.spinner_type = val.lstrip('#').lower()
        elif key == 'checked':
            ctrl.checked = vl == 'true'
        elif key == 'items':
            ctrl.items = _parse_array(val)
        elif key == 'labels':
            ctrl.labels = _parse_array(val)
        elif key == 'columns':
            try:
                ctrl.columns = int(val)
            except ValueError:
                pass
        elif key == 'readonly':
            ctrl.read_only = vl == 'true'
        elif key == 'bold':
            ctrl.bold = vl == 'true'
        elif key == 'border':
            ctrl.border = vl == 'true'
        elif key == 'fieldwidth':
            try:
                ctrl.field_width = int(float(val))
            except ValueError:
                pass
        elif key == 'orient':
            ctrl.orient = val.lstrip('#').lower()
        elif key == 'ticks':
            try:
                ctrl.ticks = int(val)
            except ValueError:
                pass
        elif key == 'numcurves':
            try:
                ctrl.num_curves = int(val)
            except ValueError:
                pass
        elif key == 'style':
            ctrl.style = val.lstrip('#').lower()
        elif key == 'modal':
            ctrl.modal = vl == 'true'
        elif key == 'filter':
            ctrl.filter = _unquote(val)
        elif key == 'address':
            ctrl.address = _unquote(val)


# ---------------------------------------------------------------------------
# Rollout body parser
# ---------------------------------------------------------------------------
def _parse_rollout_body(
    lines: list[str],
    body_start: int,
    body_end: int,
) -> tuple[list[ControlModel], dict[tuple[str,str], str], list[str], list[str]]:
    """
    Parse lines[body_start:body_end] as the content of a rollout block.
    Returns (controls, event_bodies, extra_lines, warnings).
    """
    controls: list[ControlModel] = []
    event_bodies: dict[tuple[str, str], str] = {}
    extra_lines: list[str] = []
    warnings: list[str] = []

    body = lines[body_start:body_end]
    i = 0
    while i < len(body):
        raw = body[i]
        stripped = raw.strip()

        if not stripped or stripped.startswith('--'):
            extra_lines.append(raw)
            i += 1
            continue

        # event handler
        on_m = _ON_RE.match(raw)
        if on_m:
            ctrl_name = on_m.group(1)
            event_name = on_m.group(2)
            args_str = on_m.group(3).strip()
            i += 1
            # collect body
            if i < len(body) and body[i].strip() == '(':
                # multi-line block
                depth = 0
                block: list[str] = []
                while i < len(body):
                    line = body[i]
                    depth += line.count('(') - line.count(')')
                    block.append(line)
                    i += 1
                    if depth <= 0:
                        break
                body_code = ''.join(block)
            elif i < len(body):
                body_code = body[i]
                i += 1
            else:
                body_code = ''

            event_bodies[(ctrl_name, event_name)] = body_code
            for ctrl in controls:
                if ctrl.name == ctrl_name:
                    ctrl.event_handlers.append(
                        EventHandler(event=event_name, args=args_str, code=body_code)
                    )
                    break
            else:
                warnings.append(
                    f"Event 'on {ctrl_name} {event_name}' has no matching control declaration."
                )
            continue

        # control declaration
        ctrl_m = _CTRL_TYPE_RE.match(raw)
        if ctrl_m:
            ct = ctrl_m.group(1).lower()
            cname = ctrl_m.group(2)
            rest = ctrl_m.group(3).strip()
            ctrl = ControlModel(control_type=ct, name=cname)
            if rest.startswith('"'):
                lm = re.match(r'"((?:[^"\\]|\\.)*)"(.*)', rest)
                if lm:
                    ctrl.label = lm.group(1)
                    rest = lm.group(2).strip()
            _apply_params(ctrl, _parse_params(rest))
            controls.append(ctrl)
            i += 1
            continue

        extra_lines.append(raw)
        i += 1

    return controls, event_bodies, extra_lines, warnings


# ---------------------------------------------------------------------------
# Main file scanner — finds all rollout blocks
# ---------------------------------------------------------------------------
def parse_ms_file(path: str) -> ParsedMS:
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        text = f.read()

    lines = text.splitlines(keepends=True)
    result = ParsedMS()
    i = 0
    text_buf: list[str] = []

    while i < len(lines):
        line = lines[i]
        m = _ROLLOUT_RE.match(line)

        if not m:
            text_buf.append(line)
            i += 1
            continue

        # --- Found a rollout ---
        # flush accumulated text
        if text_buf:
            result.segments.append(TextSegment(''.join(text_buf)))
            text_buf = []

        indent = m.group(1)
        rname  = m.group(2)
        rtitle = m.group(3)
        rparams = _parse_params(m.group(4))

        model = RolloutModel(rollout_name=rname, rollout_title=rtitle)
        if 'width' in rparams:
            try:
                model.width = int(float(rparams['width']))
            except ValueError:
                pass
        if 'height' in rparams:
            try:
                model.height = int(float(rparams['height']))
                model.use_height = True
            except ValueError:
                pass
        if 'pos' in rparams:
            x, y = _parse_vec2(rparams['pos'])
            model.pos_x, model.pos_y = int(x), int(y)
            model.use_pos = True

        # find opening paren
        open_idx = i
        if '(' not in line:
            for j in range(i + 1, min(i + 3, len(lines))):
                if '(' in lines[j]:
                    open_idx = j
                    break

        body_start = open_idx + 1

        # scan for matching close paren
        depth = 0
        rollout_end = body_start
        for k in range(open_idx, len(lines)):
            depth += lines[k].count('(') - lines[k].count(')')
            if k >= body_start and depth <= 0:
                rollout_end = k
                break

        # parse body
        controls, event_bodies, extra_lines, warnings = _parse_rollout_body(
            lines, body_start, rollout_end
        )
        model.controls = controls

        seg = RolloutSegment(
            model=model,
            rollout_indent=indent,
            event_bodies=event_bodies,
            extra_lines=extra_lines,
            parse_warnings=warnings,
        )
        result.segments.append(seg)
        result.parse_warnings.extend(warnings)

        # closing ')' line + newline after
        i = rollout_end + 1

    if text_buf:
        result.segments.append(TextSegment(''.join(text_buf)))

    if not result.rollout_segments:
        result.parse_warnings.append("No rollout blocks found in file.")

    return result
