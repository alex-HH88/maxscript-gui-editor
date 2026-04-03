from __future__ import annotations
"""
Data models for the MAXScript GUI Editor.
All models are JSON-serializable dataclasses.
"""
APP_VERSION = "1.29"
from dataclasses import dataclass, field, asdict
from typing import Optional
import copy
import json


# ---------------------------------------------------------------------------
# Control types and their default display sizes on the canvas
# ---------------------------------------------------------------------------
CONTROL_TYPES = [
    "button", "checkbutton", "checkbox", "colorpicker", "combobox",
    "dropdownlist", "edittext", "groupbox", "imgTag", "label", "listbox",
    "mapbutton", "materialbutton", "multilistbox", "pickbutton",
    "progressbar", "radiobuttons", "slider", "spinner",
    "timer", "bitmap", "curvecontrol", "angle", "hyperlink",
]

CONTROL_DEFAULTS: dict[str, dict] = {
    "button":          {"width": 90,  "height": 20, "label": "Button"},
    "checkbutton":     {"width": 90,  "height": 20, "label": "CheckBtn"},
    "checkbox":        {"width": 90,  "height": 16, "label": "Checkbox"},
    "colorpicker":     {"width": 90,  "height": 16, "label": "Color"},
    "combobox":        {"width": 120, "height": 20, "label": "ComboBox"},
    "dropdownlist":    {"width": 120, "height": 20, "label": "DropDown"},
    "edittext":        {"width": 120, "height": 20, "label": "EditText"},
    "groupbox":        {"width": 160, "height": 80, "label": "Group"},
    "imgTag":          {"width": 100, "height": 60, "label": ""},
    "label":           {"width": 90,  "height": 16, "label": "Label"},
    "listbox":         {"width": 120, "height": 60, "label": "ListBox"},
    "mapbutton":       {"width": 90,  "height": 20, "label": "Map"},
    "materialbutton":  {"width": 90,  "height": 20, "label": "Material"},
    "multilistbox":    {"width": 120, "height": 60, "label": "MultiList"},
    "pickbutton":      {"width": 90,  "height": 20, "label": "Pick"},
    "progressbar":     {"width": 150, "height": 14, "label": ""},
    "radiobuttons":    {"width": 120, "height": 50, "label": "Radio"},
    "slider":          {"width": 150, "height": 28, "label": "Slider"},
    "spinner":         {"width": 90,  "height": 16, "label": "Spinner"},
    "timer":           {"width": 60,  "height": 16, "label": ""},
    "bitmap":          {"width": 100, "height": 60, "label": ""},
    "curvecontrol":    {"width": 150, "height": 100,"label": ""},
    "angle":           {"width": 80,  "height": 80, "label": "Angle"},
    "hyperlink":       {"width": 120, "height": 16, "label": "Click here"},
}


@dataclass
class EventHandler:
    event: str = "pressed"
    args: str = ""
    code: str = "\t-- code here\n"

    def clone(self) -> "EventHandler":
        return copy.deepcopy(self)


@dataclass
class ControlModel:
    control_type: str = "button"
    name: str = "btn_1"
    label: str = "Button"
    # Canvas position (absolute, used for pos: parameter)
    x: int = 10
    y: int = 10
    width: int = 90
    height: int = 20
    use_pos: bool = True
    use_width: bool = False
    use_height: bool = False
    # Common layout
    across: int = 0          # 0 = not set
    align: str = ""          # "", "left", "center", "right"
    offset_x: int = 0
    offset_y: int = 0
    use_offset: bool = False
    enabled: bool = True
    visible: bool = True
    tooltip: str = ""
    comment: str = ""
    # Type-specific extras (stored as flat optional fields)
    checked: bool = False
    range_min: float = 0.0
    range_max: float = 100.0
    range_val: float = 0.0
    spinner_type: str = "float"  # float / integer
    items: list[str] = field(default_factory=list)
    labels: list[str] = field(default_factory=list)
    columns: int = 1
    read_only: bool = False
    bold: bool = False
    border: bool = False
    field_width: int = 45
    address: str = ""        # hyperlink
    orient: str = "horizontal"  # slider orientation
    ticks: int = 0
    num_curves: int = 1      # curvecontrol
    style: str = "bmp_stretch"  # imgTag
    modal: bool = False      # colorpicker / pickbutton
    filter: str = ""         # pickbutton
    event_handlers: list[EventHandler] = field(default_factory=list)

    def clone(self) -> "ControlModel":
        return copy.deepcopy(self)

    def to_dict(self) -> dict:
        d = asdict(self)
        return d

    @staticmethod
    def from_dict(d: dict) -> "ControlModel":
        ehs = [EventHandler(**e) for e in d.pop("event_handlers", [])]
        m = ControlModel(**d)
        m.event_handlers = ehs
        return m


@dataclass
class MacroScriptConfig:
    script_name: str = "MyTool"
    category: str = "Tools"
    internal_name: str = "MyTool"
    tooltip: str = "My Tool"
    button_text: str = "My Tool"
    output_mode: str = "rollout"   # "rollout" or "macroscript"

    def to_dict(self) -> dict:
        return asdict(self)

    @staticmethod
    def from_dict(d: dict) -> "MacroScriptConfig":
        return MacroScriptConfig(**d)


@dataclass
class RolloutModel:
    rollout_name: str = "RL_Rollout"
    rollout_title: str = "My Rollout"
    width: int = 330
    height: int = 500
    use_width: bool = False
    use_height: bool = False
    use_pos: bool = False
    pos_x: int = 100
    pos_y: int = 100
    controls: list[ControlModel] = field(default_factory=list)
    macro_config: MacroScriptConfig = field(default_factory=MacroScriptConfig)

    def clone(self) -> "RolloutModel":
        return copy.deepcopy(self)

    def to_dict(self) -> dict:
        d = asdict(self)
        return d

    @staticmethod
    def from_dict(d: dict) -> "RolloutModel":
        controls = [ControlModel.from_dict(c) for c in d.pop("controls", [])]
        mc = MacroScriptConfig.from_dict(d.pop("macro_config", {}))
        m = RolloutModel(**d)
        m.controls = controls
        m.macro_config = mc
        return m

    def save_json(self, path: str) -> None:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(self.to_dict(), f, indent=2)

    @staticmethod
    def load_json(path: str) -> "RolloutModel":
        with open(path, "r", encoding="utf-8") as f:
            return RolloutModel.from_dict(json.load(f))

    def get_unique_name(self, base: str) -> str:
        existing = {c.name for c in self.controls}
        if base not in existing:
            return base
        i = 1
        while f"{base}_{i}" in existing:
            i += 1
        return f"{base}_{i}"

    def add_control(self, control_type: str, x: int = 10, y: int = 10) -> ControlModel:
        defaults = CONTROL_DEFAULTS.get(control_type, {"width": 90, "height": 20, "label": control_type})
        prefix_map = {
            "button": "btn", "checkbutton": "chkbtn", "checkbox": "chk",
            "colorpicker": "clr", "combobox": "ddl", "edittext": "edt",
            "groupbox": "grp", "imgTag": "img", "label": "lbl",
            "listbox": "lbx", "mapbutton": "map", "materialbutton": "mat",
            "multilistbox": "mlb", "pickbutton": "pck", "progressbar": "prg",
            "radiobuttons": "rdo", "slider": "sld", "spinner": "spn",
            "timer": "tmr", "bitmap": "bmp", "curvecontrol": "crv",
            "angle": "ang", "hyperlink": "lnk",
        }
        prefix = prefix_map.get(control_type, "ctl")
        name = self.get_unique_name(f"{prefix}_1")
        ctrl = ControlModel(
            control_type=control_type,
            name=name,
            label=defaults.get("label", control_type),
            x=x, y=y,
            width=defaults["width"],
            height=defaults["height"],
        )
        self.controls.append(ctrl)
        return ctrl
