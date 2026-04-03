"""
Main application window.
Layout:
  Left   : Control palette (drag source) + delete button
  Centre : RolloutCanvas (WYSIWYG)
  Right  : PropertiesPanel (tabs)
  Bottom : Code output + copy/generate/send buttons
"""
from __future__ import annotations
import copy
import json
import re
from pathlib import Path
from typing import Optional

from PySide6.QtCore import Qt, QMimeData, QSize, Signal, QObject
from PySide6.QtGui import (
    QAction, QDrag, QFont, QKeySequence, QColor,
)
from PySide6.QtWidgets import (
    QMainWindow, QWidget, QSplitter, QVBoxLayout, QHBoxLayout,
    QToolBar, QPushButton, QLabel, QListWidget, QListWidgetItem,
    QTextEdit, QFileDialog, QMessageBox, QStatusBar, QGroupBox,
    QSizePolicy, QApplication, QDialog, QFormLayout, QLineEdit,
    QSpinBox, QCheckBox, QDialogButtonBox, QDoubleSpinBox, QComboBox,
)

from .bridge import MaxBridge, BridgeConfig
from .models import RolloutModel, ControlModel, CONTROL_TYPES, CONTROL_DEFAULTS, APP_VERSION
from .canvas import RolloutCanvas
from .properties_panel import PropertiesPanel
from .code_generator import generate_code
from .ms_parser import parse_ms_file, ParsedMS
from .ms_writer import write_ms_file


# ---------------------------------------------------------------------------
# Thread-safe bridge result dispatcher (Fix Bug #5 / #6)
# ---------------------------------------------------------------------------
class _BridgeResult(QObject):
    ok  = Signal(str)
    err = Signal(str)


_STYLE = """
QMainWindow, QWidget { background: #252526; color: #CCCCCC; }
QSplitter::handle { background: #3C3C3C; }
QGroupBox { border: 1px solid #3C3C3C; border-radius: 4px; margin-top: 6px; }
QGroupBox::title { subcontrol-origin: margin; left: 8px; color: #888888; }
QListWidget { background: #1E1E1E; border: 1px solid #3C3C3C; color: #CCCCCC; }
QListWidget::item:selected { background: #264F78; }
QListWidget::item:hover { background: #2A2D2E; }
QPushButton {
    background: #3C3C3C; color: #CCCCCC; border: 1px solid #555;
    border-radius: 3px; padding: 4px 10px;
}
QPushButton:hover { background: #4C4C4C; }
QPushButton:pressed { background: #264F78; }
QPushButton.danger { background: #6A1E1E; }
QPushButton.danger:hover { background: #8A2E2E; }
QLineEdit, QSpinBox, QDoubleSpinBox, QComboBox, QTextEdit {
    background: #1E1E1E; color: #CCCCCC;
    border: 1px solid #3C3C3C; border-radius: 2px; padding: 2px;
}
QTabWidget::pane { border: 1px solid #3C3C3C; }
QTabBar::tab { background: #2D2D2D; color: #888; padding: 5px 12px; }
QTabBar::tab:selected { background: #1E1E1E; color: #CCCCCC; }
QScrollBar:vertical { background: #1E1E1E; width: 8px; }
QScrollBar::handle:vertical { background: #3C3C3C; border-radius: 4px; }
QLabel { color: #CCCCCC; }
QToolBar { background: #2D2D2D; border-bottom: 1px solid #3C3C3C; spacing: 4px; }
QStatusBar { background: #007ACC; color: #FFFFFF; }
"""

_CATEGORY_ORDER = [
    ("Input",    ["button", "checkbutton", "checkbox", "pickbutton",
                  "mapbutton", "materialbutton"]),
    ("Value",    ["spinner", "slider", "angle", "colorpicker", "progressbar"]),
    ("List",     ["combobox", "dropdownlist", "listbox", "multilistbox", "radiobuttons"]),
    ("Text",     ["label", "edittext", "hyperlink"]),
    ("Display",  ["imgTag", "bitmap", "curvecontrol", "groupbox"]),
    ("Other",    ["timer"]),
]


# ---------------------------------------------------------------------------
class ControlPalette(QWidget):
    """Left panel: categorised list of draggable control types."""

    def __init__(self, parent=None):
        super().__init__(parent)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(4, 4, 4, 4)
        layout.setSpacing(4)

        lbl = QLabel("Controls")
        lbl.setFont(QFont("Segoe UI", 9, QFont.Bold))
        layout.addWidget(lbl)

        self._list = QListWidget()
        self._list.setDragEnabled(True)
        self._list.setSelectionMode(QListWidget.SingleSelection)
        layout.addWidget(self._list)

        # populate
        for category, types in _CATEGORY_ORDER:
            header = QListWidgetItem(f"── {category} ──")
            header.setFlags(Qt.NoItemFlags)
            header.setForeground(QColor("#888888"))
            self._list.addItem(header)
            for ct in types:
                item = QListWidgetItem(f"  {ct}")
                item.setData(Qt.UserRole, ct)
                self._list.addItem(item)

        self._list.startDrag = self._start_drag  # type: ignore

    def _start_drag(self, actions):
        item = self._list.currentItem()
        if item is None or item.data(Qt.UserRole) is None:
            return
        ct = item.data(Qt.UserRole)
        mime = QMimeData()
        mime.setText(ct)
        drag = QDrag(self._list)
        drag.setMimeData(mime)
        drag.exec(Qt.CopyAction)

    def selected_type(self) -> Optional[str]:
        item = self._list.currentItem()
        if item:
            return item.data(Qt.UserRole)
        return None


# ---------------------------------------------------------------------------
class MainWindow(QMainWindow):

    def __init__(self):
        super().__init__()
        self.setWindowTitle(f"MAXScript GUI Editor v{APP_VERSION}")
        self.resize(1280, 780)
        self.setStyleSheet(_STYLE)

        self._model = RolloutModel()
        self._undo_stack: list[RolloutModel] = []
        self._redo_stack: list[RolloutModel] = []
        self._current_file: Optional[Path] = None
        self._dirty = False
        self._bridge_config = BridgeConfig()
        self._bridge = MaxBridge(self._bridge_config)
        self._load_bridge_config()
        self._parsed_ms: Optional[ParsedMS] = None   # active .ms round-trip state
        self._active_rollout_idx: int = 0             # Fix Bug #9/10

        self._init_ui()
        self._init_menu()
        self._init_toolbar()
        self._canvas.load_model(self._model)
        self._props.load_model(self._model)
        self._update_title()

    # ------------------------------------------------------------------
    def _init_ui(self):
        central = QWidget()
        self.setCentralWidget(central)
        root = QHBoxLayout(central)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        # Main horizontal splitter: palette | canvas | properties
        h_split = QSplitter(Qt.Horizontal)
        root.addWidget(h_split)

        # --- Left: palette ---
        left = QWidget()
        left_l = QVBoxLayout(left)
        left_l.setContentsMargins(4, 4, 4, 4)
        self._palette = ControlPalette()
        left_l.addWidget(self._palette)

        btn_add = QPushButton("Add →")
        btn_add.setToolTip("Add selected control to canvas (or drag it)")
        btn_add.clicked.connect(self._add_from_palette)
        left_l.addWidget(btn_add)

        btn_del = QPushButton("Delete")
        btn_del.setProperty("class", "danger")
        btn_del.setStyleSheet("background:#6A1E1E;")
        btn_del.setToolTip("Delete selected control (Del)")
        btn_del.clicked.connect(self._delete_selected)
        left_l.addWidget(btn_del)

        left.setMaximumWidth(160)
        left.setMinimumWidth(130)
        h_split.addWidget(left)

        # --- Centre: canvas + code output ---
        centre = QWidget()
        centre_l = QVBoxLayout(centre)
        centre_l.setContentsMargins(0, 0, 0, 0)
        centre_l.setSpacing(2)

        self._canvas = RolloutCanvas()
        centre_l.addWidget(self._canvas, stretch=3)

        # Code output area
        code_grp = QGroupBox("Generated MAXScript")
        code_grp_l = QVBoxLayout(code_grp)
        code_grp_l.setContentsMargins(4, 4, 4, 4)
        self._code_out = QTextEdit()
        self._code_out.setFont(QFont("Consolas", 9))
        self._code_out.setReadOnly(True)
        self._code_out.setMaximumHeight(180)
        code_grp_l.addWidget(self._code_out)
        btn_row = QHBoxLayout()
        btn_gen = QPushButton("Generate Code")
        btn_gen.clicked.connect(self._generate_code)
        btn_cpy = QPushButton("Copy to Clipboard")
        btn_cpy.clicked.connect(self._copy_code)
        self._btn_send = QPushButton("▶  Send to Max")
        self._btn_send.setToolTip("Send generated code directly to 3ds Max via TCP bridge")
        self._btn_send.setStyleSheet("background:#1A4A1A; font-weight:bold;")
        self._btn_send.clicked.connect(self._send_to_max)
        self._btn_ping = QPushButton("⬤ Ping")
        self._btn_ping.setToolTip("Test connection to 3ds Max bridge listener")
        self._btn_ping.setFixedWidth(60)
        self._btn_ping.clicked.connect(self._ping_max)
        btn_row.addWidget(btn_gen)
        btn_row.addWidget(btn_cpy)
        btn_row.addWidget(self._btn_send)
        btn_row.addWidget(self._btn_ping)
        btn_row.addStretch()
        code_grp_l.addLayout(btn_row)
        centre_l.addWidget(code_grp, stretch=0)

        h_split.addWidget(centre)

        # --- Right: properties ---
        self._props = PropertiesPanel()
        self._props.setMinimumWidth(280)
        self._props.setMaximumWidth(400)
        h_split.addWidget(self._props)

        h_split.setStretchFactor(0, 0)
        h_split.setStretchFactor(1, 1)
        h_split.setStretchFactor(2, 0)
        h_split.setSizes([145, 780, 320])

        # Signals
        self._canvas.signals.control_selected.connect(self._on_ctrl_selected)
        self._canvas.signals.model_changed.connect(self._on_model_changed)
        self._props.model_changed.connect(self._on_props_changed)

        # Status bar
        self._status = QStatusBar()
        self.setStatusBar(self._status)
        self._status.showMessage("Ready — drag controls onto the canvas or click 'Add →'")

    def _init_menu(self):
        mb = self.menuBar()

        # File
        fm = mb.addMenu("File")
        a_new    = QAction("New",                 self); a_new.setShortcut("Ctrl+N")
        a_open   = QAction("Open Layout (.json)…",self); a_open.setShortcut("Ctrl+O")
        a_save   = QAction("Save",                self); a_save.setShortcut("Ctrl+S")
        a_saveas = QAction("Save As…",            self); a_saveas.setShortcut("Ctrl+Shift+S")
        a_imp_ms = QAction("Open .ms File…",      self); a_imp_ms.setShortcut("Ctrl+Shift+O")
        a_sav_ms = QAction("Save back to .ms",    self); a_sav_ms.setShortcut("Ctrl+Shift+M")
        a_quit   = QAction("Quit",                self); a_quit.setShortcut("Ctrl+Q")
        a_new.triggered.connect(self._new)
        a_open.triggered.connect(self._open)
        a_save.triggered.connect(self._save)
        a_saveas.triggered.connect(self._save_as)
        a_imp_ms.triggered.connect(self._open_ms)
        a_sav_ms.triggered.connect(self._save_ms)
        a_quit.triggered.connect(self.close)
        fm.addAction(a_new)
        fm.addAction(a_open)
        fm.addAction(a_save)
        fm.addAction(a_saveas)
        fm.addSeparator()
        fm.addAction(a_imp_ms)
        fm.addAction(a_sav_ms)
        fm.addSeparator()
        fm.addAction(a_quit)

        # Edit
        em = mb.addMenu("Edit")
        a_undo = QAction("Undo", self); a_undo.setShortcut("Ctrl+Z")
        a_redo = QAction("Redo", self); a_redo.setShortcut("Ctrl+Y")
        a_del  = QAction("Delete Control", self); a_del.setShortcut("Del")
        a_dup  = QAction("Duplicate Control", self); a_dup.setShortcut("Ctrl+D")
        a_undo.triggered.connect(self._undo)
        a_redo.triggered.connect(self._redo)
        a_del.triggered.connect(self._delete_selected)
        a_dup.triggered.connect(self._duplicate_selected)
        em.addActions([a_undo, a_redo])
        em.addSeparator()
        em.addActions([a_del, a_dup])

        # Code
        cm = mb.addMenu("Code")
        a_gen  = QAction("Generate Code",        self); a_gen.setShortcut("F5")
        a_cpy  = QAction("Copy to Clipboard",    self); a_cpy.setShortcut("Ctrl+Shift+C")
        a_send = QAction("Send to Max",          self); a_send.setShortcut("F6")
        a_ping = QAction("Ping 3ds Max",         self)
        a_bcfg = QAction("Bridge Settings…",     self)
        a_gen.triggered.connect(self._generate_code)
        a_cpy.triggered.connect(self._copy_code)
        a_send.triggered.connect(self._send_to_max)
        a_ping.triggered.connect(self._ping_max)
        a_bcfg.triggered.connect(self._bridge_settings)
        cm.addActions([a_gen, a_cpy, cm.addSeparator(), a_send, a_ping, a_bcfg])

    def _init_toolbar(self):
        tb = self.addToolBar("Main")
        tb.setMovable(False)
        tb.setIconSize(QSize(16, 16))
        tb.addAction("New",      self._new)
        tb.addAction("Open",     self._open)
        tb.addAction("Save",     self._save)
        tb.addSeparator()
        tb.addAction("Undo",     self._undo)
        tb.addAction("Redo",     self._redo)
        tb.addSeparator()
        tb.addAction("Delete",   self._delete_selected)
        tb.addAction("Duplicate",self._duplicate_selected)
        tb.addSeparator()
        tb.addAction("Generate", self._generate_code)
        tb.addAction("Copy",     self._copy_code)
        tb.addSeparator()
        tb.addAction("▶ Send to Max",  self._send_to_max)
        tb.addAction("Bridge…",        self._bridge_settings)
        tb.addSeparator()
        # Rollout picker — visible only when a .ms file with multiple rollouts is open
        self._tb_rollout_label = QLabel("  Rollout: ")
        self._tb_rollout_label.setStyleSheet("color:#888888;")
        tb.addWidget(self._tb_rollout_label)
        self._tb_rollout_picker = QComboBox()
        self._tb_rollout_picker.setMinimumWidth(180)
        self._tb_rollout_picker.setToolTip("Switch between rollout blocks in the loaded .ms file")
        self._tb_rollout_picker.currentIndexChanged.connect(self._on_rollout_picked)
        tb.addWidget(self._tb_rollout_picker)
        self._tb_rollout_label.setVisible(False)
        self._tb_rollout_picker.setVisible(False)

    # ------------------------------------------------------------------
    # Undo / Redo
    # ------------------------------------------------------------------
    def _push_undo(self):
        self._undo_stack.append(copy.deepcopy(self._model))
        if len(self._undo_stack) > 50:
            self._undo_stack.pop(0)
        self._redo_stack.clear()

    def _undo(self):
        if not self._undo_stack:
            return
        self._redo_stack.append(copy.deepcopy(self._model))
        self._model = self._undo_stack.pop()
        self._reload_all()
        self._status.showMessage("Undo")

    def _redo(self):
        if not self._redo_stack:
            return
        self._undo_stack.append(copy.deepcopy(self._model))
        self._model = self._redo_stack.pop()
        self._reload_all()
        self._status.showMessage("Redo")

    def _reload_all(self):
        self._canvas.load_model(self._model)
        self._props.load_model(self._model)
        self._props.select_control(None)
        self._update_title()

    # ------------------------------------------------------------------
    # Canvas/props signals
    # ------------------------------------------------------------------
    def _on_ctrl_selected(self, ctrl: Optional[ControlModel]):
        self._props.select_control(ctrl)
        if ctrl:
            self._status.showMessage(f"Selected: {ctrl.name} ({ctrl.control_type})")
        else:
            self._status.showMessage("Ready")

    def _on_model_changed(self):
        self._push_undo()
        self._dirty = True
        self._update_title()

    def _on_props_changed(self):
        # refresh canvas item for the currently selected control
        sel = [c for c in self._model.controls
               if self._canvas._items.get(id(c)) and
               self._canvas._items[id(c)].isSelected()]
        for c in sel:
            self._canvas.refresh_item(c)
        self._dirty = True
        self._update_title()

    # ------------------------------------------------------------------
    # Control operations
    # ------------------------------------------------------------------
    def _add_from_palette(self):
        ct = self._palette.selected_type()
        if ct:
            self._push_undo()
            ctrl = self._canvas.add_control(ct)
            self._props.select_control(ctrl)
            self._dirty = True
            self._update_title()
            self._status.showMessage(f"Added {ct}: {ctrl.name}")

    def _delete_selected(self):
        self._push_undo()
        self._canvas.delete_selected()
        self._props.select_control(None)
        self._dirty = True
        self._update_title()

    def _duplicate_selected(self):
        sel_items = [i for i in self._canvas.scene().selectedItems()
                     if hasattr(i, "model")]
        if not sel_items:
            return
        self._push_undo()
        for item in sel_items:
            orig: ControlModel = item.model
            new_ctrl = copy.deepcopy(orig)
            new_ctrl.x = orig.x + 16
            new_ctrl.y = orig.y + 16
            new_ctrl.name = self._model.get_unique_name(orig.name)
            self._model.controls.append(new_ctrl)
            added = self._canvas._add_item(new_ctrl)
            self._canvas.scene().clearSelection()
            added.setSelected(True)
        self._dirty = True
        self._update_title()

    # ------------------------------------------------------------------
    # Code generation
    # ------------------------------------------------------------------
    def _generate_code(self):
        code = generate_code(self._model)
        self._code_out.setPlainText(code)
        self._status.showMessage("Code generated.")

    def _copy_code(self):
        code = self._code_out.toPlainText()
        if not code:
            code = generate_code(self._model)
            self._code_out.setPlainText(code)
        QApplication.clipboard().setText(code)
        self._status.showMessage("Code copied to clipboard.")

    # ------------------------------------------------------------------
    # File I/O
    # ------------------------------------------------------------------
    def _confirm_discard(self) -> bool:
        if not self._dirty:
            return True
        r = QMessageBox.question(self, "Unsaved changes",
                                 "Discard unsaved changes?",
                                 QMessageBox.Yes | QMessageBox.Cancel)
        return r == QMessageBox.Yes

    def _new(self):
        if not self._confirm_discard():
            return
        self._model = RolloutModel()
        self._current_file = None
        self._dirty = False
        self._parsed_ms = None
        self._undo_stack.clear()
        self._redo_stack.clear()
        self._tb_rollout_picker.setVisible(False)
        self._tb_rollout_label.setVisible(False)
        self._tb_rollout_picker.clear()
        self._reload_all()
        self._code_out.clear()
        self._status.showMessage("New layout created.")

    def _open(self):
        if not self._confirm_discard():
            return
        path, _ = QFileDialog.getOpenFileName(
            self, "Open Layout", "", "JSON Layout (*.json);;All files (*)"
        )
        if not path:
            return
        try:
            self._model = RolloutModel.load_json(path)
            self._current_file = Path(path)
            self._dirty = False
            self._parsed_ms = None
            self._undo_stack.clear()
            self._redo_stack.clear()
            self._reload_all()
            self._status.showMessage(f"Loaded: {path}")
        except Exception as e:
            QMessageBox.critical(self, "Load Error", str(e))

    def _save(self):
        if self._current_file:
            self._do_save(self._current_file)
        else:
            self._save_as()

    def _save_as(self):
        path, _ = QFileDialog.getSaveFileName(
            self, "Save Layout", "", "JSON Layout (*.json);;All files (*)"
        )
        if path:
            self._do_save(Path(path))

    def _do_save(self, path: Path):
        try:
            self._model.save_json(str(path))
            self._current_file = path
            self._dirty = False
            self._update_title()
            self._status.showMessage(f"Saved: {path}")
        except Exception as e:
            QMessageBox.critical(self, "Save Error", str(e))

    # ------------------------------------------------------------------
    # .ms round-trip import / export
    # ------------------------------------------------------------------
    # Patch dynamic control properties from on-open handler bodies
    # ------------------------------------------------------------------
    @staticmethod
    def _patch_dynamic_properties(seg) -> None:
        """
        Scans all event handler bodies in a RolloutSegment for dynamic
        property assignments and writes them back into ControlModel fields:
          ctrl.labels  = #("a","b")   → radiobuttons.labels
          ctrl.items   = #("a","b")   → combobox/listbox/dropdownlist.items
          ctrl.enabled = false        → ctrl.enabled
          ctrl.visible = false        → ctrl.visible
          ctrl.checked = true/false   → checkbox/checkbutton.checked
        """
        ctrl_map = {c.name: c for c in seg.model.controls}
        if not ctrl_map:
            return

        _LABELS_RE  = re.compile(r'\b(\w+)\.labels\s*=\s*#\(([^)]+)\)',  re.IGNORECASE)
        _ITEMS_RE   = re.compile(r'\b(\w+)\.items\s*=\s*#\(([^)]+)\)',   re.IGNORECASE)
        _BOOL_RE    = re.compile(r'\b(\w+)\.(enabled|visible|checked)\s*=\s*(true|false)', re.IGNORECASE)
        _STR_RE     = re.compile(r'"([^"]*)"')

        def _apply(text: str) -> None:
            for m in _LABELS_RE.finditer(text):
                c = ctrl_map.get(m.group(1))
                if c:
                    vals = _STR_RE.findall(m.group(2))
                    if vals:
                        c.labels = vals
            for m in _ITEMS_RE.finditer(text):
                c = ctrl_map.get(m.group(1))
                if c:
                    vals = _STR_RE.findall(m.group(2))
                    if vals:
                        c.items = vals
            for m in _BOOL_RE.finditer(text):
                c = ctrl_map.get(m.group(1))
                if c:
                    val = m.group(3).lower() == "true"
                    prop = m.group(2).lower()
                    if prop == "enabled":
                        c.enabled = val
                    elif prop == "visible":
                        c.visible = val
                    elif prop == "checked":
                        c.checked = val

        for body_code in seg.event_bodies.values():
            _apply(body_code)
        for raw in seg.orphaned_events:
            _apply(raw)

    def _open_ms(self):
        if not self._confirm_discard():
            return
        path, _ = QFileDialog.getOpenFileName(
            self, "Open MAXScript File", "",
            "MAXScript Files (*.ms);;All files (*)"
        )
        if not path:
            return
        try:
            parsed = parse_ms_file(path)
            segs = parsed.rollout_segments
            if not segs:
                QMessageBox.warning(self, "Open .ms",
                    "No rollout blocks found in this file.\n"
                    "The file may use dynamic control creation which cannot be parsed.")
                return

            # Patch dynamic properties from on-open handler bodies
            for seg in segs:
                self._patch_dynamic_properties(seg)

            self._parsed_ms = parsed
            self._current_file = Path(path)
            self._dirty = False
            self._undo_stack.clear()
            self._redo_stack.clear()

            # populate rollout picker (Fix Bug #7: try/finally ensures blockSignals reset)
            self._tb_rollout_picker.blockSignals(True)
            try:
                self._tb_rollout_picker.clear()
                for seg in segs:
                    label = f"{seg.model.rollout_name}  ({len(seg.model.controls)} controls)"
                    self._tb_rollout_picker.addItem(label)
            finally:
                self._tb_rollout_picker.blockSignals(False)

            show_picker = len(segs) > 1
            self._tb_rollout_label.setVisible(show_picker)
            self._tb_rollout_picker.setVisible(show_picker)

            # load first rollout
            self._load_rollout_segment(0)

            if parsed.parse_warnings:
                QMessageBox.information(self, "Parse Warnings",
                    "\n".join(parsed.parse_warnings))
        except Exception as e:
            QMessageBox.critical(self, "Open .ms Error", str(e))

    def _load_rollout_segment(self, idx: int):
        segs = self._parsed_ms.rollout_segments
        if idx < 0 or idx >= len(segs):   # Fix Bug #2
            return
        seg = segs[idx]
        self._active_rollout_idx = idx     # Fix Bug #9/10
        self._model = seg.model
        self._reload_all()
        n = len(segs)
        ctrl_count = len(seg.model.controls)
        self._status.showMessage(
            f"{'[.ms]  ' if n == 1 else f'[.ms  {idx+1}/{n}]  '}"
            f"{seg.model.rollout_name}  ·  {ctrl_count} controls"
            f"  ·  Ctrl+Shift+M = save all"
        )

    def _on_rollout_picked(self, idx: int):
        if self._parsed_ms is None or idx < 0:
            return
        # sync current model back before switching
        self._sync_active_rollout()
        self._load_rollout_segment(idx)

    def _sync_active_rollout(self):
        """Write self._model back into the active RolloutSegment."""
        if self._parsed_ms is None:
            return
        idx = self._active_rollout_idx   # Fix Bug #9/10: use tracked idx, not currentIndex()
        segs = self._parsed_ms.rollout_segments
        if 0 <= idx < len(segs):
            segs[idx].model = self._model

    def _save_ms(self):
        if self._parsed_ms is None:
            QMessageBox.information(self, "Save to .ms",
                "No .ms file is loaded.\nUse  File > Open .ms File…  first.")
            return
        # sync currently active rollout
        self._sync_active_rollout()
        try:
            write_ms_file(self._parsed_ms, str(self._current_file))
            self._dirty = False
            self._update_title()
            n = len(self._parsed_ms.rollout_segments)
            self._status.showMessage(
                f"Saved .ms: {self._current_file.name}  ·  {n} rollout(s)"
            )
        except Exception as e:
            QMessageBox.critical(self, "Save .ms Error", str(e))

    def _update_ms_indicator(self):
        pass  # replaced by _load_rollout_segment status message

    # ------------------------------------------------------------------
    # Bridge
    # ------------------------------------------------------------------
    def _bridge_cfg_path(self) -> Path:
        return Path.home() / ".maxscript_gui_editor" / "bridge.json"

    def _load_bridge_config(self):
        p = self._bridge_cfg_path()
        if p.exists():
            try:
                with open(p) as f:
                    self._bridge_config = BridgeConfig.from_dict(json.load(f))
                    self._bridge = MaxBridge(self._bridge_config)
            except Exception:
                pass

    def _save_bridge_config(self):
        p = self._bridge_cfg_path()
        p.parent.mkdir(parents=True, exist_ok=True)
        with open(p, "w") as f:
            json.dump(self._bridge_config.to_dict(), f, indent=2)

    def _bridge_settings(self):
        dlg = BridgeSettingsDialog(self._bridge_config, self)
        if dlg.exec() == QDialog.Accepted:
            self._bridge_config = dlg.get_config()
            self._bridge = MaxBridge(self._bridge_config)
            self._save_bridge_config()
            self._status.showMessage(
                f"Bridge: {self._bridge_config.host}:{self._bridge_config.port}"
            )

    def _send_to_max(self):
        code = self._code_out.toPlainText()
        if not code:
            code = generate_code(self._model)
            self._code_out.setPlainText(code)

        # In rollout mode: clear queue, close existing dialog, open fresh one
        if self._model.macro_config.output_mode != "macroscript":
            rname = self._model.rollout_name
            code = (f"_bridgePendingCode = #()\n"
                    f"try ( destroyDialog {rname} ) catch ()\n"
                    + code +
                    f"\ncreateDialog {rname}")

        # If rollout title is a dynamic expression, guard any undefined globals
        # e.g. ("vrscene  v" + VRSCENE_TOOLS_VERSION) → prepend guard
        import re as _re
        title = self._model.rollout_title
        if title.startswith("("):
            caps_vars = _re.findall(r'\b([A-Z][A-Z0-9_]{2,})\b', title)
            if caps_vars:
                guards = "\n".join(
                    f'if {v} == undefined do global {v} = "1.0"'
                    for v in dict.fromkeys(caps_vars)  # deduplicate, preserve order
                )
                code = guards + "\n" + code

        # MAXScript bit.intAsChar doesn't handle tab (byte 9) — use spaces
        code = code.replace("\t", "    ")

        self._btn_send.setEnabled(False)
        self._btn_send.setText("Sending…")
        self._status.showMessage("Sending code to 3ds Max…")

        # Fix Bug #5/#6: signals cross thread boundary safely — no direct widget calls
        result = _BridgeResult(self)

        def _restore():
            self._btn_send.setEnabled(True)
            self._btn_send.setText("▶  Send to Max")

        result.ok.connect(lambda resp: (_restore(), self._status.showMessage(f"3ds Max: {resp}")))
        result.err.connect(lambda msg: (_restore(),
                                        self._status.showMessage("Bridge error — see dialog"),
                                        QMessageBox.warning(self, "Bridge Error", msg)))

        self._bridge.send_async(code, result.ok.emit, result.err.emit)

    def _ping_max(self):
        self._status.showMessage("Pinging 3ds Max…")
        self._btn_ping.setEnabled(False)

        result = _BridgeResult(self)

        def _done():
            self._btn_ping.setEnabled(True)

        result.ok.connect(lambda msg: (
            _done(),
            self._btn_ping.setStyleSheet("color:#4CAF50; font-weight:bold;"),
            self._status.showMessage(f"3ds Max reachable — {msg}"),
        ))
        result.err.connect(lambda msg: (
            _done(),
            self._btn_ping.setStyleSheet("color:#F44336; font-weight:bold;"),
            self._status.showMessage("3ds Max not reachable"),
            QMessageBox.warning(self, "Bridge Ping", msg),
        ))

        self._bridge.send_async("-- ping", result.ok.emit, result.err.emit)

    # ------------------------------------------------------------------
    def _update_title(self):
        name = self._current_file.name if self._current_file else "Untitled"
        dirty = " *" if self._dirty else ""
        self.setWindowTitle(f"MAXScript GUI Editor v{APP_VERSION} — {name}{dirty}")


# ---------------------------------------------------------------------------
# Bridge Settings Dialog
# ---------------------------------------------------------------------------
class BridgeSettingsDialog(QDialog):
    def __init__(self, config: BridgeConfig, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Bridge Settings — 3ds Max Connection")
        self.setMinimumWidth(380)
        self._cfg = BridgeConfig(**config.to_dict())

        layout = QVBoxLayout(self)

        info = QLabel(
            "<b>TCP Bridge to 3ds Max</b><br>"
            "Run <code>max_bridge_listener.ms</code> inside 3ds Max first.<br>"
            "Default: 127.0.0.1 : 27120"
        )
        info.setTextFormat(Qt.RichText)
        info.setWordWrap(True)
        layout.addWidget(info)

        form = QFormLayout()
        form.setLabelAlignment(Qt.AlignRight)

        self._host = QLineEdit(self._cfg.host)
        self._host.textChanged.connect(lambda v: setattr(self._cfg, "host", v))
        form.addRow("Host:", self._host)

        self._port = QSpinBox()
        self._port.setRange(1024, 65535)
        self._port.setValue(self._cfg.port)
        self._port.valueChanged.connect(lambda v: setattr(self._cfg, "port", v))
        form.addRow("Port:", self._port)

        self._timeout = QDoubleSpinBox()
        self._timeout.setRange(0.5, 30.0)
        self._timeout.setSingleStep(0.5)
        self._timeout.setValue(self._cfg.timeout)
        self._timeout.valueChanged.connect(lambda v: setattr(self._cfg, "timeout", v))
        form.addRow("Timeout (s):", self._timeout)

        layout.addLayout(form)

        # Ping button
        ping_row = QHBoxLayout()
        btn_ping = QPushButton("Test Connection")
        self._ping_result = QLabel("")
        btn_ping.clicked.connect(self._do_ping)
        ping_row.addWidget(btn_ping)
        ping_row.addWidget(self._ping_result)
        ping_row.addStretch()
        layout.addLayout(ping_row)

        # How to use
        howto = QLabel(
            "<hr><b>How to start the listener in 3ds Max:</b><br>"
            "Scripting → Run Script → select <code>max_bridge_listener.ms</code><br>"
            "The script auto-starts and prints the port to the MAXScript Listener."
        )
        howto.setTextFormat(Qt.RichText)
        howto.setWordWrap(True)
        layout.addWidget(howto)

        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def _do_ping(self):
        bridge = MaxBridge(self._cfg)
        ok, msg = bridge.ping()
        if ok:
            self._ping_result.setText("✓ Connected")
            self._ping_result.setStyleSheet("color:#4CAF50; font-weight:bold;")
        else:
            self._ping_result.setText("✗ Failed")
            self._ping_result.setStyleSheet("color:#F44336;")

    def get_config(self) -> BridgeConfig:
        return self._cfg
