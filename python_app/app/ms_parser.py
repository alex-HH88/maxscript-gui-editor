"""
MAXScript .ms file parser — round-trip safe.

Strategy
--------
The file is split into three zones:
  pre_rollout   — everything before the rollout block (untouched)
  rollout_body  — the rollout block itself (controls parsed, event bodies preserved)
  post_rollout  — everything after the rollout block (untouched)

Only control DECLARATION lines are read into the model.
Event handler DO-bodies are stored verbatim and written back unchanged.
All other code (globals, functions, macroScript wrapper, comments) is preserved.
"""
from __future__ import annotations
import re
from dataclasses import dataclass, field
from typing import Optional

from .models import RolloutModel, ControlModel, EventHandler, CONTROL_TYPES


# ---------------------------------------------------------------------------
# Result container
# ---------------------------------------------------------------------------
@dataclass
class ParsedMS:
    """
    Round-trip container for a .ms file.
    Only the rollout block is touched; everything else is preserved verbatim.
    """
    pre_rollout: str = ""          # text before  'rollout XYZ ...'
    post_rollout: str = ""         # text after closing ')' of the rollout
    rollout_indent: str = ""       # leading whitespace of the rollout line
    model: RolloutModel = field(default_factory=RolloutModel)
    # Raw event-handler bodies keyed by (ctrl_name, event)
    # e.g. ("btn_ok", "pressed") -> "    doSomething()\n"
    event_bodies: dict[tuple[str, str], str] = field(default_factory=dict)
    # Lines inside the rollout that are NOT control decls or event handlers
    # (comments, local vars, etc.) — stored with their position index so we
    # can interleave them when writing back.
    # List of (line_index_in_rollout_body, raw_line_str)
    extra_lines: list[tuple[int, str]] = field(default_factory=list)
    parse_warnings: list[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Parameter tokenizer helpers
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
    """Parse  #("a","b","c")  or  #(1,2,3)  into a list of strings."""
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


def _parse_params(param_str: str) -> dict[str, str]:
    """
    Tokenize  key:value  pairs from a parameter string.
    Handles nested brackets  [...]  and  #(...)  as single values.
    Returns dict of lowercase-key → raw-value-string.
    """
    result: dict[str, str] = {}
    s = param_str.strip()
    while s:
        # find next key:
        km = re.match(r'(\w+)\s*:', s)
        if not km:
            break
        key = km.group(1).lower()
        s = s[km.end():].lstrip()
        # collect value until next bare key: or end
        val, s = _consume_value(s)
        result[key] = val.strip()
    return result


def _consume_value(s: str) -> tuple[str, str]:
    """Consume one value token from the start of s, return (value, remainder)."""
    if not s:
        return '', ''
    # quoted string
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
    # #(...) array
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
    # #name  (symbol like #float, #left)
    if s.startswith('#'):
        m = re.match(r'(#\w+)', s)
        if m:
            return m.group(1), s[m.end():].lstrip()
    # [...] vector
    if s[0] == '[':
        end = s.index(']') + 1 if ']' in s else len(s)
        return s[:end], s[end:].lstrip()
    # plain token (number, bool, word)
    m = re.match(r'([^\s:,]+)', s)
    if m:
        return m.group(1), s[m.end():].lstrip()
    return s, ''


def _apply_params(ctrl: ControlModel, params: dict[str, str]) -> None:
    """Write parsed parameter dict into a ControlModel."""
    for key, val in params.items():
        vl = val.lower()
        if key == 'pos':
            x, y = _parse_vec2(val)
            ctrl.x, ctrl.y = int(x), int(y)
            ctrl.use_pos = True
        elif key == 'width':
            try:
                ctrl.width = int(float(val))
                ctrl.use_width = True
            except ValueError:
                pass
        elif key == 'height':
            try:
                ctrl.height = int(float(val))
                ctrl.use_height = True
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
# Block collector — reads lines until matching closing paren
# ---------------------------------------------------------------------------
def _collect_block(lines: list[str], start: int) -> tuple[list[str], int]:
    """
    Starting from start (the line containing the opening '('),
    collect lines until the matching ')'.  Returns (body_lines, next_idx).
    """
    depth = 0
    body: list[str] = []
    i = start
    while i < len(lines):
        line = lines[i]
        depth += line.count('(') - line.count(')')
        body.append(line)
        i += 1
        if depth <= 0:
            break
    return body, i


# ---------------------------------------------------------------------------
# Main parser
# ---------------------------------------------------------------------------
def parse_ms_file(path: str) -> ParsedMS:
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        text = f.read()

    lines = text.splitlines(keepends=True)
    result = ParsedMS()

    # --- 1. Locate the rollout block ---
    rollout_start = -1
    for i, line in enumerate(lines):
        m = _ROLLOUT_RE.match(line)
        if m:
            rollout_start = i
            result.rollout_indent = m.group(1)
            result.model.rollout_name = m.group(2)
            result.model.rollout_title = m.group(3)
            # parse rollout-level params (width, pos, height)
            extra = m.group(4)
            rp = _parse_params(extra)
            if 'width' in rp:
                try:
                    result.model.width = int(float(rp['width']))
                except ValueError:
                    pass
            if 'height' in rp:
                try:
                    result.model.height = int(float(rp['height']))
                    result.model.use_height = True
                except ValueError:
                    pass
            if 'pos' in rp:
                x, y = _parse_vec2(rp['pos'])
                result.model.pos_x, result.model.pos_y = int(x), int(y)
                result.model.use_pos = True
            break

    if rollout_start == -1:
        result.parse_warnings.append("No rollout block found in file.")
        result.pre_rollout = text
        return result

    result.pre_rollout = ''.join(lines[:rollout_start])

    # --- 2. Find the rollout body block ---
    # The opening '(' is either on the rollout line or the next line
    body_start = rollout_start + 1
    # Find the line with opening paren
    open_line = rollout_start
    if '(' not in lines[rollout_start]:
        for j in range(rollout_start + 1, min(rollout_start + 3, len(lines))):
            if '(' in lines[j]:
                open_line = j
                body_start = j + 1
                break
    else:
        body_start = rollout_start + 1

    # Collect until matching close paren
    depth = 0
    rollout_end = body_start
    for i in range(open_line, len(lines)):
        depth += lines[i].count('(') - lines[i].count(')')
        if i >= body_start and depth <= 0:
            rollout_end = i + 1
            break

    result.post_rollout = ''.join(lines[rollout_end:])
    body_lines = lines[body_start:rollout_end - 1]  # exclude closing ')'

    # --- 3. Parse body lines ---
    i = 0
    line_idx = 0
    while i < len(body_lines):
        raw = body_lines[i]
        stripped = raw.strip()

        # skip blank lines and comments
        if not stripped or stripped.startswith('--'):
            result.extra_lines.append((line_idx, raw))
            i += 1
            line_idx += 1
            continue

        # event handler:  on <ctrl> <event> [args] do
        on_m = _ON_RE.match(raw)
        if on_m:
            ctrl_name = on_m.group(1)
            event_name = on_m.group(2)
            args_str = on_m.group(3).strip()
            i += 1
            # collect the DO body
            if i < len(body_lines) and body_lines[i].strip() == '(':
                body_block, consumed = _collect_block(body_lines, i)
                body_code = ''.join(body_block)
                i += consumed - i  # _collect_block already advances
            elif i < len(body_lines):
                # single-line body without parens
                body_code = body_lines[i]
                i += 1
            else:
                body_code = ''
            # attach to existing control model or store orphan
            result.event_bodies[(ctrl_name, event_name)] = body_code
            # find matching control and add EventHandler
            for ctrl in result.model.controls:
                if ctrl.name == ctrl_name:
                    eh = EventHandler(event=event_name, args=args_str,
                                      code=body_code)
                    ctrl.event_handlers.append(eh)
                    break
            else:
                result.parse_warnings.append(
                    f"Event handler 'on {ctrl_name} {event_name}' has no matching control."
                )
            line_idx += 1
            continue

        # control declaration
        ctrl_m = _CTRL_TYPE_RE.match(raw)
        if ctrl_m:
            ct = ctrl_m.group(1).lower()
            cname = ctrl_m.group(2)
            rest = ctrl_m.group(3).strip()
            ctrl = ControlModel(control_type=ct, name=cname)
            # first token of rest may be the label (quoted string)
            if rest.startswith('"'):
                lm = re.match(r'"((?:[^"\\]|\\.)*)"(.*)', rest)
                if lm:
                    ctrl.label = lm.group(1)
                    rest = lm.group(2).strip()
            params = _parse_params(rest)
            _apply_params(ctrl, params)
            result.model.controls.append(ctrl)
            i += 1
            line_idx += 1
            continue

        # anything else — preserve verbatim
        result.extra_lines.append((line_idx, raw))
        i += 1
        line_idx += 1

    return result
