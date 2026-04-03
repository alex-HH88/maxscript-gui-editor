"""
MAXScript code generator.
Takes a RolloutModel and produces clean MAXScript source.
"""
from __future__ import annotations
from .models import RolloutModel, ControlModel, MacroScriptConfig


def _q(s: str) -> str:
    """Wrap string in MAXScript double-quotes, escaping inner quotes."""
    return '"' + s.replace('"', '\\"') + '"'


def _arr(items: list[str]) -> str:
    return "#(" + ", ".join(_q(i) for i in items) + ")"


def _build_control(c: ControlModel, indent: str = "\t") -> str:
    parts: list[str] = []

    # --- comment ---
    lines: list[str] = []
    if c.comment:
        lines.append(f"{indent}-- {c.comment}")

    # --- control line ---
    params: list[str] = [_q(c.label)] if c.label and c.control_type not in (
        "timer", "progressbar", "bitmap", "imgTag", "curvecontrol"
    ) else []

    if c.use_pos:
        params.append(f"pos:[{c.x},{c.y}]")
    if c.use_width:
        params.append(f"width:{c.width}")
    if c.use_height:
        params.append(f"height:{c.height}")
    if c.use_offset:
        params.append(f"offset:[{c.offset_x},{c.offset_y}]")
    if c.across > 0:
        params.append(f"across:{c.across}")
    if c.align in ("left", "center", "right"):
        params.append(f"align:#{c.align}")
    if not c.enabled:
        params.append("enabled:false")
    if not c.visible:
        params.append("visible:false")
    if c.tooltip:
        params.append(f"toolTip:{_q(c.tooltip)}")

    # --- type-specific ---
    ct = c.control_type

    if ct == "spinner":
        params.append(f"range:[{c.range_min},{c.range_max},{c.range_val}]")
        params.append(f"type:#{c.spinner_type}")
        if c.use_width:
            pass  # already added
        if c.field_width != 45:
            params.append(f"fieldWidth:{c.field_width}")

    elif ct == "checkbox":
        if c.checked:
            params.append("checked:true")
        if c.bold:
            params.append("bold:true")

    elif ct == "checkbutton":
        if c.checked:
            params.append("checked:true")

    elif ct in ("combobox", "listbox", "multilistbox"):
        if c.items:
            params.append(f"items:{_arr(c.items)}")
        if c.use_height:
            pass  # already added
        if ct in ("listbox", "multilistbox") and c.use_height:
            pass

    elif ct == "radiobuttons":
        if c.labels:
            params.append(f"labels:{_arr(c.labels)}")
        if c.columns > 1:
            params.append(f"columns:{c.columns}")

    elif ct == "edittext":
        if c.read_only:
            params.append("readOnly:true")
        if c.field_width != 45:
            params.append(f"fieldWidth:{c.field_width}")
        if c.border:
            params.append("border:true")
        if c.bold:
            params.append("bold:true")

    elif ct == "slider":
        params.append(f"range:[{c.range_min},{c.range_max},{c.range_val}]")
        if c.orient == "vertical":
            params.append("orient:#vertical")
        if c.ticks != 0:
            params.append(f"ticks:{c.ticks}")

    elif ct == "angle":
        params.append(f"range:[{c.range_min},{c.range_max},{c.range_val}]")

    elif ct == "colorpicker":
        if c.modal:
            params.append("modal:true")

    elif ct == "pickbutton":
        if c.filter:
            params.append(f"filter:{_q(c.filter)}")
        if c.modal:
            params.append("modal:true")

    elif ct == "hyperlink":
        if c.address:
            params.append(f"address:{_q(c.address)}")

    elif ct == "imgTag":
        params.append(f"style:#{c.style}")

    elif ct == "curvecontrol":
        if c.num_curves != 1:
            params.append(f"numCurves:{c.num_curves}")

    elif ct == "progressbar":
        params.append(f"range:[{c.range_min},{c.range_max},{c.range_val}]")

    elif ct == "label":
        if c.bold:
            params.append("bold:true")
        if c.border:
            params.append("border:true")

    param_str = " ".join(params)
    line = f"{indent}{ct} {c.name} {param_str}".rstrip()
    lines.append(line)

    # --- event handlers ---
    for eh in c.event_handlers:
        args_part = f" {eh.args}" if eh.args.strip() else ""
        lines.append(f"{indent}on {c.name} {eh.event}{args_part} do")
        lines.append(f"{indent}(")
        for code_line in eh.code.splitlines():
            lines.append(f"{indent}\t{code_line}")
        lines.append(f"{indent})")

    return "\n".join(lines)


def _build_control_decl_only(c: ControlModel, indent: str = "\t") -> str:
    """Like _build_control but WITHOUT event handler blocks.
    Used by the round-trip writer so event bodies can be written verbatim."""
    import copy as _copy
    tmp = _copy.copy(c)
    tmp.event_handlers = []
    return _build_control(tmp, indent)


def build_rollout_code(model: RolloutModel) -> str:
    """Generate a plain rollout block."""
    lines: list[str] = []

    title_part = model.rollout_title if model.rollout_title.startswith('(') else _q(model.rollout_title)
    header_params: list[str] = [title_part]
    if model.use_pos:
        header_params.append(f"pos:[{model.pos_x},{model.pos_y}]")
    if model.use_width:
        header_params.append(f"width:{model.width}")
    if model.use_height:
        header_params.append(f"height:{model.height}")

    lines.append(f"rollout {model.rollout_name} {' '.join(header_params)}")
    lines.append("(")

    for ctrl in model.controls:
        lines.append(_build_control(ctrl, indent="\t"))

    lines.append(")")
    return "\n".join(lines)


def build_macroscript_code(model: RolloutModel) -> str:
    """Generate a full MacroScript wrapping the rollout."""
    cfg: MacroScriptConfig = model.macro_config
    lines: list[str] = []

    lines.append(f'macroScript {cfg.internal_name}')
    lines.append(f'\tcategory:{_q(cfg.category)}')
    lines.append(f'\tinternalName:{_q(cfg.internal_name)}')
    lines.append(f'\ttoolTip:{_q(cfg.tooltip)}')
    lines.append(f'\tbuttonText:{_q(cfg.button_text)}')
    lines.append("(")
    lines.append("\t-- persistent window position")
    lines.append(f"\tpersistent global {cfg.internal_name}_pos")
    lines.append("")

    # rollout block indented
    rollout_code = build_rollout_code(model)
    for l in rollout_code.splitlines():
        lines.append("\t" + l)

    lines.append("")
    lines.append("\ton execute do")
    lines.append("\t(")
    lines.append(f"\t\tif {cfg.internal_name}_pos == undefined do {cfg.internal_name}_pos = [100,100]")
    lines.append(f"\t\t{model.rollout_name}.pos = {cfg.internal_name}_pos")
    lines.append(f"\t\tcreateDialog {model.rollout_name} width:{model.width}")
    lines.append("\t)")
    lines.append("")
    lines.append("\ton isChecked return")
    lines.append(f"\t\t(isRolloutOpen {model.rollout_name})")
    lines.append(")")

    return "\n".join(lines)


def generate_code(model: RolloutModel) -> str:
    """Entry point: picks rollout or macroscript mode from macro_config."""
    if model.macro_config.output_mode == "macroscript":
        return build_macroscript_code(model)
    return build_rollout_code(model)
