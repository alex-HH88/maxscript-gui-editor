"""
Properties panel — dynamically updates to show the selected control's properties.
Also contains tabs for: Control | Rollout | MacroScript | Event Handlers
"""
from __future__ import annotations
from typing import Optional, Callable

from PySide6.QtCore import Qt, Signal, QObject
from PySide6.QtGui import QFont
from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QFormLayout, QTabWidget,
    QLabel, QLineEdit, QCheckBox, QComboBox, QSpinBox, QDoubleSpinBox,
    QGroupBox, QPushButton, QTextEdit, QListWidget, QListWidgetItem,
    QScrollArea, QSizePolicy, QFrame, QToolButton,
)

from .models import ControlModel, RolloutModel, MacroScriptConfig, EventHandler, CONTROL_TYPES


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _row(label: str, widget: QWidget) -> tuple[QLabel, QWidget]:
    lbl = QLabel(label)
    lbl.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
    return lbl, widget


def _section(title: str) -> QGroupBox:
    gb = QGroupBox(title)
    gb.setStyleSheet("QGroupBox { font-weight: bold; margin-top: 6px; }"
                     "QGroupBox::title { subcontrol-origin: margin; left: 6px; }")
    return gb


# ---------------------------------------------------------------------------
# EventHandlerEditor  (embedded in a tab)
# ---------------------------------------------------------------------------
class EventHandlerEditor(QWidget):
    changed = Signal()

    # Events available per control type
    _EVENTS: dict[str, list[str]] = {
        "button":          ["pressed"],
        "checkbutton":     ["changed", "pressed"],
        "checkbox":        ["changed"],
        "colorpicker":     ["changed"],
        "combobox":        ["selected", "changed"],
        "edittext":        ["changed", "entered"],
        "listbox":         ["selected", "doubleClicked"],
        "multilistbox":    ["selected"],
        "radiobuttons":    ["changed"],
        "slider":          ["changed", "buttondown", "buttonup"],
        "spinner":         ["changed", "buttondown", "buttonup"],
        "angle":           ["changed", "buttondown", "buttonup"],
        "pickbutton":      ["picked", "rightclick"],
        "mapbutton":       ["picked", "rightclick"],
        "materialbutton":  ["picked", "rightclick"],
        "progressbar":     [],
        "timer":           ["tick"],
        "imgTag":          ["click"],
        "hyperlink":       [],
        "curvecontrol":    ["change"],
        "bitmap":          [],
        "label":           ["click"],
        "groupbox":        [],
    }

    def __init__(self, parent=None):
        super().__init__(parent)
        self._ctrl: Optional[ControlModel] = None
        self._building = False
        self._init_ui()

    def _init_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(4, 4, 4, 4)

        # list of handlers
        self._list = QListWidget()
        self._list.setMaximumHeight(90)
        self._list.currentRowChanged.connect(self._on_list_sel)
        layout.addWidget(self._list)

        # add/remove buttons
        btn_row = QHBoxLayout()
        self._cmb_event = QComboBox()
        self._cmb_event.setMinimumWidth(100)
        btn_row.addWidget(self._cmb_event)
        btn_add = QToolButton(); btn_add.setText("+")
        btn_add.clicked.connect(self._add_handler)
        btn_row.addWidget(btn_add)
        btn_del = QToolButton(); btn_del.setText("−")
        btn_del.clicked.connect(self._del_handler)
        btn_row.addWidget(btn_del)
        btn_row.addStretch()
        layout.addLayout(btn_row)

        # code editor
        lbl = QLabel("Code:")
        layout.addWidget(lbl)
        self._code = QTextEdit()
        self._code.setFont(QFont("Consolas", 9))
        self._code.setMinimumHeight(120)
        self._code.textChanged.connect(self._on_code_changed)
        layout.addWidget(self._code)

    def load(self, ctrl: Optional[ControlModel]):
        self._ctrl = ctrl
        self._building = True
        self._list.clear()
        self._code.clear()
        if ctrl is None:
            self._building = False
            return
        events = self._EVENTS.get(ctrl.control_type, ["pressed"])
        self._cmb_event.clear()
        self._cmb_event.addItems(events if events else ["pressed"])
        for eh in ctrl.event_handlers:
            self._list.addItem(f"on {ctrl.name} {eh.event}")
        if self._list.count() > 0:
            self._list.setCurrentRow(0)
        self._building = False

    def _on_list_sel(self, row: int):
        if self._ctrl is None or row < 0 or row >= len(self._ctrl.event_handlers):
            return
        self._building = True
        eh = self._ctrl.event_handlers[row]
        self._code.setPlainText(eh.code)
        self._building = False

    def _on_code_changed(self):
        if self._building or self._ctrl is None:
            return
        row = self._list.currentRow()
        if 0 <= row < len(self._ctrl.event_handlers):
            self._ctrl.event_handlers[row].code = self._code.toPlainText()
            self.changed.emit()

    def _add_handler(self):
        if self._ctrl is None:
            return
        event = self._cmb_event.currentText() or "pressed"
        eh = EventHandler(event=event)
        self._ctrl.event_handlers.append(eh)
        self._list.addItem(f"on {self._ctrl.name} {event}")
        self._list.setCurrentRow(len(self._ctrl.event_handlers) - 1)
        self.changed.emit()

    def _del_handler(self):
        if self._ctrl is None:
            return
        row = self._list.currentRow()
        if 0 <= row < len(self._ctrl.event_handlers):
            del self._ctrl.event_handlers[row]
            self._list.takeItem(row)
            self.changed.emit()


# ---------------------------------------------------------------------------
# ControlPropertiesWidget
# ---------------------------------------------------------------------------
class ControlPropertiesWidget(QWidget):
    changed = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._ctrl: Optional[ControlModel] = None
        self._building = False
        self._init_ui()

    def _init_ui(self):
        scroll = QScrollArea(self)
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.NoFrame)
        inner = QWidget()
        self._form = QFormLayout(inner)
        self._form.setLabelAlignment(Qt.AlignRight)
        self._form.setContentsMargins(6, 6, 6, 6)
        self._form.setSpacing(4)
        scroll.setWidget(inner)
        main = QVBoxLayout(self)
        main.setContentsMargins(0, 0, 0, 0)
        main.addWidget(scroll)
        self._inner = inner
        self._scroll = scroll

    def _clear(self):
        while self._form.rowCount():
            self._form.removeRow(0)
        self._widgets: dict[str, QWidget] = {}

    def _add(self, key: str, label: str, widget: QWidget):
        self._form.addRow(label + ":", widget)
        self._widgets[key] = widget

    def _le(self, key: str, label: str, val: str):
        w = QLineEdit(val)
        w.textChanged.connect(lambda v, k=key: self._set(k, v))
        self._add(key, label, w)

    def _chk(self, key: str, label: str, val: bool):
        w = QCheckBox()
        w.setChecked(val)
        w.toggled.connect(lambda v, k=key: self._set(k, v))
        self._add(key, label, w)

    def _cmb(self, key: str, label: str, options: list[str], val: str):
        w = QComboBox()
        w.addItems(options)
        idx = w.findText(val)
        if idx >= 0:
            w.setCurrentIndex(idx)
        w.currentTextChanged.connect(lambda v, k=key: self._set(k, v))
        self._add(key, label, w)

    def _spin(self, key: str, label: str, val: int, lo: int = 0, hi: int = 9999):
        w = QSpinBox()
        w.setRange(lo, hi)
        w.setValue(val)
        w.valueChanged.connect(lambda v, k=key: self._set(k, v))
        self._add(key, label, w)

    def _dspin(self, key: str, label: str, val: float, lo: float = -1e6, hi: float = 1e6):
        w = QDoubleSpinBox()
        w.setRange(lo, hi)
        w.setDecimals(3)
        w.setValue(val)
        w.valueChanged.connect(lambda v, k=key: self._set(k, v))
        self._add(key, label, w)

    def _items_editor(self, key: str, label: str, items: list[str]):
        w = QTextEdit()
        w.setPlainText("\n".join(items))
        w.setMaximumHeight(80)
        w.textChanged.connect(lambda k=key, ww=w: self._set(k, [s for s in ww.toPlainText().splitlines() if s.strip()]))
        self._add(key, label, w)

    def _set(self, key: str, val):
        if self._building or self._ctrl is None:
            return
        setattr(self._ctrl, key, val)
        self.changed.emit()

    # ------------------------------------------------------------------
    def load(self, ctrl: Optional[ControlModel]):
        self._ctrl = ctrl
        self._building = True
        self._clear()
        if ctrl is None:
            self._building = False
            return

        ct = ctrl.control_type

        # --- always present ---
        self._le("name",    "Name",    ctrl.name)
        self._le("label",   "Label",   ctrl.label)
        self._le("tooltip", "Tooltip", ctrl.tooltip)
        self._le("comment", "Comment", ctrl.comment)

        # --- position ---
        self._form.addRow(QLabel("─── Layout ───"))
        self._chk("use_pos",  "Use pos",  ctrl.use_pos)
        self._spin("x",       "X",        ctrl.x)
        self._spin("y",       "Y",        ctrl.y)
        self._chk("use_width",  "Use width",  ctrl.use_width)
        self._spin("width",     "Width",      ctrl.width, 1, 2000)
        self._chk("use_height", "Use height", ctrl.use_height)
        self._spin("height",    "Height",     ctrl.height, 1, 2000)
        self._spin("across",    "Across (0=off)", ctrl.across, 0, 20)
        self._cmb("align", "Align", ["", "left", "center", "right"], ctrl.align)
        self._chk("use_offset", "Use offset", ctrl.use_offset)
        self._spin("offset_x", "Offset X", ctrl.offset_x, -500, 500)
        self._spin("offset_y", "Offset Y", ctrl.offset_y, -500, 500)
        self._chk("enabled", "Enabled", ctrl.enabled)
        self._chk("visible", "Visible", ctrl.visible)

        # --- type-specific ---
        self._form.addRow(QLabel(f"─── {ct} ───"))

        if ct == "spinner":
            self._dspin("range_min", "Min",    ctrl.range_min)
            self._dspin("range_max", "Max",    ctrl.range_max)
            self._dspin("range_val", "Value",  ctrl.range_val)
            self._cmb("spinner_type", "Type", ["float", "integer", "worldunits"], ctrl.spinner_type)
            self._spin("field_width", "Field width", ctrl.field_width, 10, 500)

        elif ct in ("slider", "angle"):
            self._dspin("range_min", "Min",   ctrl.range_min)
            self._dspin("range_max", "Max",   ctrl.range_max)
            self._dspin("range_val", "Value", ctrl.range_val)
            if ct == "slider":
                self._cmb("orient", "Orient", ["horizontal", "vertical"], ctrl.orient)
                self._spin("ticks", "Ticks", ctrl.ticks, 0, 100)

        elif ct in ("checkbox", "checkbutton"):
            self._chk("checked", "Checked", ctrl.checked)
            if ct == "checkbox":
                self._chk("bold", "Bold", ctrl.bold)

        elif ct in ("combobox", "listbox", "multilistbox"):
            self._items_editor("items", "Items\n(one/line)", ctrl.items)

        elif ct == "radiobuttons":
            self._items_editor("labels", "Labels\n(one/line)", ctrl.labels)
            self._spin("columns", "Columns", ctrl.columns, 1, 10)

        elif ct == "edittext":
            self._chk("read_only",  "Read only",   ctrl.read_only)
            self._chk("bold",       "Bold",        ctrl.bold)
            self._chk("border",     "Border",      ctrl.border)
            self._spin("field_width","Field width", ctrl.field_width, 10, 500)

        elif ct == "colorpicker":
            self._chk("modal", "Modal", ctrl.modal)

        elif ct == "pickbutton":
            self._le("filter", "Filter", ctrl.filter)
            self._chk("modal", "Modal", ctrl.modal)

        elif ct == "hyperlink":
            self._le("address", "Address", ctrl.address)

        elif ct == "imgTag":
            self._cmb("style", "Style",
                       ["bmp_stretch", "bmp_tile", "bmp_center"], ctrl.style)

        elif ct == "curvecontrol":
            self._spin("num_curves", "Num curves", ctrl.num_curves, 1, 16)

        elif ct == "progressbar":
            self._dspin("range_min", "Min",   ctrl.range_min)
            self._dspin("range_max", "Max",   ctrl.range_max)
            self._dspin("range_val", "Value", ctrl.range_val)

        elif ct == "label":
            self._chk("bold",   "Bold",   ctrl.bold)
            self._chk("border", "Border", ctrl.border)

        self._building = False


# ---------------------------------------------------------------------------
# RolloutPropertiesWidget
# ---------------------------------------------------------------------------
class RolloutPropertiesWidget(QWidget):
    changed = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._model: Optional[RolloutModel] = None
        self._building = False
        self._init_ui()

    def _init_ui(self):
        layout = QFormLayout(self)
        layout.setLabelAlignment(Qt.AlignRight)
        layout.setContentsMargins(8, 8, 8, 8)
        layout.setSpacing(4)

        def le(attr, label, default=""):
            w = QLineEdit()
            w.textChanged.connect(lambda v, a=attr: self._set(a, v))
            layout.addRow(label + ":", w)
            return w

        def spin(attr, label, lo=0, hi=9999):
            w = QSpinBox(); w.setRange(lo, hi)
            w.valueChanged.connect(lambda v, a=attr: self._set(a, v))
            layout.addRow(label + ":", w)
            return w

        def chk(attr, label):
            w = QCheckBox()
            w.toggled.connect(lambda v, a=attr: self._set(a, v))
            layout.addRow(label + ":", w)
            return w

        self._name   = le("rollout_name",  "Name")
        self._title  = le("rollout_title", "Title")
        self._width  = spin("width",  "Width",  100, 2000)
        self._height = spin("height", "Height", 50,  2000)
        self._use_h  = chk("use_height", "Use height")
        self._use_p  = chk("use_pos",    "Use pos")
        self._pos_x  = spin("pos_x", "Pos X", 0, 9999)
        self._pos_y  = spin("pos_y", "Pos Y", 0, 9999)

    def _set(self, attr, val):
        if self._building or self._model is None:
            return
        setattr(self._model, attr, val)
        self.changed.emit()

    def load(self, model: RolloutModel):
        self._model = model
        self._building = True
        self._name.setText(model.rollout_name)
        self._title.setText(model.rollout_title)
        self._width.setValue(model.width)
        self._height.setValue(model.height)
        self._use_h.setChecked(model.use_height)
        self._use_p.setChecked(model.use_pos)
        self._pos_x.setValue(model.pos_x)
        self._pos_y.setValue(model.pos_y)
        self._building = False


# ---------------------------------------------------------------------------
# MacroScriptPropertiesWidget
# ---------------------------------------------------------------------------
class MacroScriptPropertiesWidget(QWidget):
    changed = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._cfg: Optional[MacroScriptConfig] = None
        self._building = False
        self._init_ui()

    def _init_ui(self):
        layout = QFormLayout(self)
        layout.setLabelAlignment(Qt.AlignRight)
        layout.setContentsMargins(8, 8, 8, 8)
        layout.setSpacing(4)

        def le(attr, label):
            w = QLineEdit()
            w.textChanged.connect(lambda v, a=attr: self._set(a, v))
            layout.addRow(label + ":", w)
            return w

        self._mode  = QComboBox()
        self._mode.addItems(["rollout", "macroscript"])
        self._mode.currentTextChanged.connect(lambda v: self._set("output_mode", v))
        layout.addRow("Output mode:", self._mode)

        self._sname = le("script_name",   "Script name")
        self._cat   = le("category",      "Category")
        self._iname = le("internal_name", "Internal name")
        self._tip   = le("tooltip",       "Tooltip")
        self._btxt  = le("button_text",   "Button text")

    def _set(self, attr, val):
        if self._building or self._cfg is None:
            return
        setattr(self._cfg, attr, val)
        self.changed.emit()

    def load(self, cfg: MacroScriptConfig):
        self._cfg = cfg
        self._building = True
        idx = self._mode.findText(cfg.output_mode)
        self._mode.setCurrentIndex(max(0, idx))
        self._sname.setText(cfg.script_name)
        self._cat.setText(cfg.category)
        self._iname.setText(cfg.internal_name)
        self._tip.setText(cfg.tooltip)
        self._btxt.setText(cfg.button_text)
        self._building = False


# ---------------------------------------------------------------------------
# PropertiesPanel — tab container for all sub-panels
# ---------------------------------------------------------------------------
class PropertiesPanel(QWidget):
    model_changed = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._model: Optional[RolloutModel] = None
        self._init_ui()

    def _init_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)

        self._tabs = QTabWidget()
        layout.addWidget(self._tabs)

        # Tab 1 – Control
        self._ctrl_panel = ControlPropertiesWidget()
        self._ctrl_panel.changed.connect(self.model_changed)
        self._tabs.addTab(self._ctrl_panel, "Control")

        # Tab 2 – Events
        self._ev_panel = EventHandlerEditor()
        self._ev_panel.changed.connect(self.model_changed)
        self._tabs.addTab(self._ev_panel, "Events")

        # Tab 3 – Rollout
        self._rl_panel = RolloutPropertiesWidget()
        self._rl_panel.changed.connect(self.model_changed)
        self._tabs.addTab(self._rl_panel, "Rollout")

        # Tab 4 – MacroScript
        self._ms_panel = MacroScriptPropertiesWidget()
        self._ms_panel.changed.connect(self.model_changed)
        self._tabs.addTab(self._ms_panel, "MacroScript")

    def load_model(self, model: RolloutModel):
        self._model = model
        self._rl_panel.load(model)
        self._ms_panel.load(model.macro_config)

    def select_control(self, ctrl: Optional[ControlModel]):
        self._ctrl_panel.load(ctrl)
        self._ev_panel.load(ctrl)
        if ctrl is not None:
            self._tabs.setCurrentIndex(0)
