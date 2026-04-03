"""
MAXScript GUI Editor — Standalone Python App
Entry point: python main.py

Requirements: PySide6  (pip install PySide6)
"""
import sys
from PySide6.QtWidgets import QApplication
from PySide6.QtCore import Qt
from app.main_window import MainWindow


def main():
    # High-DPI
    QApplication.setHighDpiScaleFactorRoundingPolicy(
        Qt.HighDpiScaleFactorRoundingPolicy.PassThrough
    )
    app = QApplication(sys.argv)
    app.setApplicationName("MAXScript GUI Editor")
    app.setOrganizationName("alex-HH88")

    win = MainWindow()
    win.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
