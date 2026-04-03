"""
WYSIWYG Canvas — QGraphicsView with drag-and-drop control placement.
Each ControlModel is represented as a ControlItem (QGraphicsItem).
"""
from __future__ import annotations
from typing import Optional, Callable

from PySide6.QtCore import Qt, QRectF, QPointF, QSizeF, Signal, QObject
from PySide6.QtGui import (
    QPainter, QColor, QPen, QBrush, QFont, QFontMetrics, QDragEnterEvent,
    QDropEvent, QMouseEvent,
)
from PySide6.QtWidgets import (
    QGraphicsView, QGraphicsScene, QGraphicsItem, QGraphicsRectItem,
    QGraphicsTextItem, QSizePolicy,
)

from .models import RolloutModel, ControlModel, CONTROL_TYPES

# ---------------------------------------------------------------------------
# Colour palette per control category
# ---------------------------------------------------------------------------
_COLORS: dict[str, tuple[str, str]] = {
    "button":         ("#4A90D9", "#FFFFFF"),
    "checkbutton":    ("#5BA85A", "#FFFFFF"),
    "checkbox":       ("#5BA85A", "#FFFFFF"),
    "colorpicker":    ("#C0783C", "#FFFFFF"),
    "combobox":       ("#7B68EE", "#FFFFFF"),
    "edittext":       ("#555E6E", "#FFFFFF"),
    "groupbox":       ("#3A3A3A", "#AAAAAA"),
    "imgTag":         ("#2E2E2E", "#888888"),
    "label":          ("#2E2E2E", "#CCCCCC"),
    "listbox":        ("#7B68EE", "#FFFFFF"),
    "mapbutton":      ("#C08030", "#FFFFFF"),
    "materialbutton": ("#C08030", "#FFFFFF"),
    "multilistbox":   ("#7B68EE", "#FFFFFF"),
    "pickbutton":     ("#4A90D9", "#FFFFFF"),
    "progressbar":    ("#2E6E2E", "#FFFFFF"),
    "radiobuttons":   ("#5BA85A", "#FFFFFF"),
    "slider":         ("#888888", "#FFFFFF"),
    "spinner":        ("#555E6E", "#FFFFFF"),
    "timer":          ("#444444", "#AAAAAA"),
    "bitmap":         ("#2E2E2E", "#888888"),
    "curvecontrol":   ("#1A3A5A", "#AADDFF"),
    "angle":          ("#555E6E", "#FFFFFF"),
    "hyperlink":      ("#2E5EA8", "#88AAFF"),
}

_SEL_BORDER = "#F5A623"
_GRID_SIZE   = 4


def _snap(v: float, grid: int = _GRID_SIZE) -> int:
    return round(v / grid) * grid


# ---------------------------------------------------------------------------
# ControlItem
# ---------------------------------------------------------------------------
class ControlItem(QGraphicsItem):
    """Visual representation of one ControlModel on the canvas."""

    def __init__(self, model: ControlModel, scene_changed_cb: Callable):
        super().__init__()
        self.model = model
        self._scene_changed = scene_changed_cb
        self.setFlags(
            QGraphicsItem.ItemIsMovable |
            QGraphicsItem.ItemIsSelectable |
            QGraphicsItem.ItemSendsGeometryChanges
        )
        self.setAcceptHoverEvents(True)
        self._update_pos()

    def _update_pos(self):
        self.setPos(self.model.x, self.model.y)

    def boundingRect(self) -> QRectF:
        return QRectF(0, 0, self.model.width, self.model.height)

    def paint(self, painter: QPainter, option, widget=None):
        ct = self.model.control_type
        bg_hex, fg_hex = _COLORS.get(ct, ("#444444", "#FFFFFF"))
        bg = QColor(bg_hex)
        fg = QColor(fg_hex)

        selected = self.isSelected()
        pen = QPen(QColor(_SEL_BORDER) if selected else QColor("#666666"),
                   2 if selected else 1)
        painter.setPen(pen)
        painter.setBrush(QBrush(bg))

        r = self.boundingRect()

        if ct == "groupbox":
            painter.setOpacity(0.35)
            painter.drawRect(r)
            painter.setOpacity(1.0)
            painter.setPen(QPen(QColor(fg_hex)))
            painter.drawText(r.adjusted(4, 2, -4, -4),
                             Qt.AlignTop | Qt.AlignLeft,
                             f"[ {self.model.label or self.model.name} ]")
            return

        painter.drawRoundedRect(r, 3, 3)

        # label text
        font = QFont("Segoe UI", 7)
        if ct == "label" and self.model.bold:
            font.setBold(True)
        painter.setFont(font)
        painter.setPen(QPen(fg))

        display = self.model.label or self.model.name
        if ct == "timer":
            display = f"⏱ {self.model.name}"
        elif ct == "progressbar":
            display = ""
            rng = max(1, self.model.range_max - self.model.range_min)
            val = max(self.model.range_min, min(self.model.range_val, self.model.range_max))
            bar_w = int(r.width() * ((val - self.model.range_min) / rng))
            painter.setBrush(QBrush(QColor("#4CAF50")))
            painter.setPen(Qt.NoPen)
            painter.drawRect(QRectF(1, 1, max(0, bar_w - 2), r.height() - 2))
        elif ct == "slider":
            display = ""
            mid_y = r.height() / 2
            painter.setPen(QPen(QColor("#AAAAAA"), 2))
            painter.drawLine(QPointF(4, mid_y), QPointF(r.width() - 4, mid_y))
            rng = max(1, self.model.range_max - self.model.range_min)
            val = max(self.model.range_min, min(self.model.range_val, self.model.range_max))
            thumb_x = 4 + (r.width() - 8) * ((val - self.model.range_min) / rng)
            painter.setBrush(QBrush(QColor("#FFFFFF")))
            painter.setPen(QPen(QColor("#888888"), 1))
            painter.drawEllipse(QPointF(thumb_x, mid_y), 5, 5)
        elif ct == "checkbox":
            box_r = QRectF(2, (r.height() - 10) / 2, 10, 10)
            painter.setBrush(QBrush(QColor("#FFFFFF") if not self.model.checked else QColor("#4CAF50")))
            painter.setPen(QPen(QColor("#888888")))
            painter.drawRect(box_r)
            if self.model.checked:
                painter.setPen(QPen(QColor("#FFFFFF"), 2))
                painter.drawText(box_r, Qt.AlignCenter, "✓")
            display = "  " + (self.model.label or self.model.name)
        elif ct == "colorpicker":
            swatch = QRectF(r.width() - 22, 3, 16, r.height() - 6)
            painter.setBrush(QBrush(QColor("#E05050")))
            painter.setPen(QPen(QColor("#888888")))
            painter.drawRect(swatch)

        if display:
            painter.setPen(QPen(fg))
            painter.drawText(r.adjusted(4, 0, -4, 0), Qt.AlignCenter, display)

        # control-type badge (top-right, tiny)
        if ct not in ("label", "groupbox"):
            painter.setFont(QFont("Segoe UI", 5))
            painter.setPen(QPen(QColor(fg_hex).darker(150)))
            painter.drawText(r.adjusted(0, 1, -2, 0), Qt.AlignTop | Qt.AlignRight, ct)

    def itemChange(self, change, value):
        if change == QGraphicsItem.ItemPositionHasChanged:
            sx = _snap(self.pos().x())
            sy = _snap(self.pos().y())
            self.model.x = max(0, sx)
            self.model.y = max(0, sy)
            self._scene_changed()
        return super().itemChange(change, value)

    def mouseReleaseEvent(self, event):
        super().mouseReleaseEvent(event)
        # snap on release
        sx = _snap(self.pos().x())
        sy = _snap(self.pos().y())
        self.setPos(sx, sy)
        self.model.x = max(0, sx)
        self.model.y = max(0, sy)


# ---------------------------------------------------------------------------
# Canvas signals helper (QObject wrapper)
# ---------------------------------------------------------------------------
class CanvasSignals(QObject):
    control_selected = Signal(object)   # ControlModel or None
    model_changed    = Signal()


# ---------------------------------------------------------------------------
# RolloutCanvas
# ---------------------------------------------------------------------------
class RolloutCanvas(QGraphicsView):
    """Main canvas widget. Manages the QGraphicsScene and all ControlItems."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.signals = CanvasSignals()
        self._model: Optional[RolloutModel] = None
        self._items: dict[int, ControlItem] = {}   # id(model) -> item

        scene = QGraphicsScene(self)
        scene.setBackgroundBrush(QBrush(QColor("#1E1E1E")))
        self.setScene(scene)
        self.setRenderHint(QPainter.Antialiasing)
        self.setDragMode(QGraphicsView.RubberBandDrag)
        self.setAcceptDrops(True)
        self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        self.setMinimumSize(400, 500)

        scene.selectionChanged.connect(self._on_selection_changed)

    # ------------------------------------------------------------------
    def load_model(self, model: RolloutModel):
        self._model = model
        self._rebuild()

    def _rebuild(self):
        self.scene().clear()
        self._items.clear()
        if self._model is None:
            return
        # Canvas background rect representing the rollout dialog
        w = self._model.width
        h = self._model.height if self._model.use_height else max(
            500, max((c.y + c.height + 20 for c in self._model.controls), default=500)
        )
        bg = QGraphicsRectItem(0, 0, w, h)
        bg.setBrush(QBrush(QColor("#2D2D2D")))
        bg.setPen(QPen(QColor("#555555"), 1))
        bg.setZValue(-10)
        bg.setFlag(QGraphicsItem.ItemIsSelectable, False)
        self.scene().addItem(bg)
        self.scene().setSceneRect(-20, -20, w + 40, h + 40)

        # Draw grid dots
        for gx in range(0, w, _GRID_SIZE * 4):
            for gy in range(0, h, _GRID_SIZE * 4):
                dot = self.scene().addEllipse(gx - 0.5, gy - 0.5, 1, 1,
                                               QPen(Qt.NoPen),
                                               QBrush(QColor("#404040")))
                dot.setFlag(QGraphicsItem.ItemIsSelectable, False)
                dot.setZValue(-9)

        for ctrl in self._model.controls:
            self._add_item(ctrl)

    def _add_item(self, ctrl: ControlModel) -> ControlItem:
        item = ControlItem(ctrl, self._on_model_changed)
        self.scene().addItem(item)
        self._items[id(ctrl)] = item
        return item

    # ------------------------------------------------------------------
    def add_control(self, control_type: str) -> ControlModel:
        assert self._model is not None
        # place near centre of visible area
        center = self.mapToScene(self.viewport().rect().center())
        x = _snap(max(0, center.x() - 45))
        y = _snap(max(0, center.y() - 10))
        ctrl = self._model.add_control(control_type, x, y)
        item = self._add_item(ctrl)
        # select the new item
        self.scene().clearSelection()
        item.setSelected(True)
        self._on_model_changed()
        return ctrl

    def delete_selected(self):
        assert self._model is not None
        for item in self.scene().selectedItems():
            if isinstance(item, ControlItem):
                self._model.controls.remove(item.model)
                self.scene().removeItem(item)
                del self._items[id(item.model)]
        self._on_model_changed()

    def select_control(self, ctrl: Optional[ControlModel]):
        self.scene().clearSelection()
        if ctrl is None:
            return
        item = self._items.get(id(ctrl))
        if item:
            item.setSelected(True)

    def refresh_item(self, ctrl: ControlModel):
        item = self._items.get(id(ctrl))
        if item:
            item._update_pos()
            item.prepareGeometryChange()
            item.update()

    def refresh_all(self):
        self._rebuild()

    # ------------------------------------------------------------------
    def _on_selection_changed(self):
        sel = [i for i in self.scene().selectedItems() if isinstance(i, ControlItem)]
        self.signals.control_selected.emit(sel[0].model if sel else None)

    def _on_model_changed(self):
        self.signals.model_changed.emit()

    # ------------------------------------------------------------------
    # Drag & Drop from the control palette
    # ------------------------------------------------------------------
    def dragEnterEvent(self, event: QDragEnterEvent):
        if event.mimeData().hasText():
            event.acceptProposedAction()
        else:
            super().dragEnterEvent(event)

    def dragMoveEvent(self, event):
        if event.mimeData().hasText():
            event.acceptProposedAction()
        else:
            super().dragMoveEvent(event)

    def dropEvent(self, event: QDropEvent):
        ct = event.mimeData().text()
        if ct in CONTROL_TYPES and self._model is not None:
            pos = self.mapToScene(event.position().toPoint())
            x = _snap(max(0, int(pos.x())))
            y = _snap(max(0, int(pos.y())))
            ctrl = self._model.add_control(ct, x, y)
            item = self._add_item(ctrl)
            self.scene().clearSelection()
            item.setSelected(True)
            self._on_model_changed()
            event.acceptProposedAction()
        else:
            super().dropEvent(event)
