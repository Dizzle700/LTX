"""
VHS Restorer Client — PyQt6
Клиентское приложение для управления LTX2.3-ICEdit-Insight на RunPod

Установка:
    pip install PyQt6 requests

Запуск:
    python vhs_restorer_client.py
"""

import sys
import os
import json
import mimetypes
import time
import threading
import requests
from pathlib import Path

from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QPushButton, QLineEdit, QFileDialog, QComboBox,
    QSpinBox, QDoubleSpinBox, QProgressBar, QTextEdit, QGroupBox,
    QStatusBar, QFrame, QSplitter, QScrollArea, QMessageBox,
    QTabWidget, QCheckBox, QSlider, QGridLayout, QSizePolicy,
)
from PyQt6.QtCore import (
    Qt, QThread, pyqtSignal, QTimer, QSettings, QSize
)
from PyQt6.QtGui import (
    QFont, QIcon, QPalette, QColor, QDragEnterEvent, QDropEvent, QPixmap
)


# ─── Color palette ─────────────────────────────────────────────────────────────
DARK = {
    "bg":        "#1a1b1e",
    "bg2":       "#212226",
    "bg3":       "#2a2b30",
    "border":    "#3a3b40",
    "text":      "#e8e9ec",
    "text2":     "#9a9ba8",
    "accent":    "#7c6ff7",
    "accent2":   "#5a54c4",
    "success":   "#3ecf8e",
    "warning":   "#f0a429",
    "danger":    "#e85d5d",
    "info":      "#4a9eff",
}

STYLESHEET = f"""
QMainWindow, QWidget {{
    background-color: {DARK['bg']};
    color: {DARK['text']};
    font-family: 'Segoe UI', 'SF Pro Display', sans-serif;
    font-size: 13px;
}}
QGroupBox {{
    background-color: {DARK['bg2']};
    border: 1px solid {DARK['border']};
    border-radius: 8px;
    margin-top: 8px;
    padding: 12px 8px 8px 8px;
    font-weight: 600;
    color: {DARK['text']};
}}
QGroupBox::title {{
    subcontrol-origin: margin;
    left: 12px;
    padding: 0 6px;
    color: {DARK['accent']};
    font-size: 12px;
    letter-spacing: 0.5px;
    text-transform: uppercase;
}}
QLineEdit, QSpinBox, QDoubleSpinBox, QComboBox {{
    background-color: {DARK['bg3']};
    border: 1px solid {DARK['border']};
    border-radius: 6px;
    padding: 6px 10px;
    color: {DARK['text']};
    selection-background-color: {DARK['accent']};
}}
QLineEdit:focus, QSpinBox:focus, QDoubleSpinBox:focus, QComboBox:focus {{
    border-color: {DARK['accent']};
}}
QComboBox::drop-down {{ border: none; width: 24px; }}
QComboBox::down-arrow {{ image: none; width: 0; }}
QComboBox QAbstractItemView {{
    background-color: {DARK['bg3']};
    border: 1px solid {DARK['border']};
    selection-background-color: {DARK['accent']};
    color: {DARK['text']};
}}
QPushButton {{
    background-color: {DARK['bg3']};
    border: 1px solid {DARK['border']};
    border-radius: 6px;
    padding: 7px 16px;
    color: {DARK['text']};
    font-weight: 500;
}}
QPushButton:hover {{ background-color: {DARK['border']}; border-color: {DARK['accent']}; }}
QPushButton:pressed {{ background-color: {DARK['accent2']}; }}
QPushButton:disabled {{ color: {DARK['text2']}; border-color: {DARK['bg3']}; }}
QPushButton#primary {{
    background-color: {DARK['accent']};
    border-color: {DARK['accent']};
    color: white;
    font-weight: 600;
}}
QPushButton#primary:hover {{ background-color: {DARK['accent2']}; }}
QPushButton#danger {{
    background-color: {DARK['danger']};
    border-color: {DARK['danger']};
    color: white;
}}
QPushButton#success {{
    background-color: {DARK['success']};
    border-color: {DARK['success']};
    color: #0a2a1e;
    font-weight: 600;
}}
QProgressBar {{
    background-color: {DARK['bg3']};
    border: none;
    border-radius: 4px;
    height: 8px;
    text-align: center;
    color: transparent;
}}
QProgressBar::chunk {{
    background-color: {DARK['accent']};
    border-radius: 4px;
}}
QTextEdit {{
    background-color: {DARK['bg3']};
    border: 1px solid {DARK['border']};
    border-radius: 6px;
    color: #8bd5ca;
    font-family: 'Consolas', 'Cascadia Code', monospace;
    font-size: 11px;
    padding: 4px;
}}
QTabWidget::pane {{
    border: 1px solid {DARK['border']};
    border-radius: 8px;
    background-color: {DARK['bg2']};
}}
QTabBar::tab {{
    background-color: {DARK['bg3']};
    color: {DARK['text2']};
    padding: 8px 18px;
    border-radius: 6px 6px 0 0;
    margin-right: 2px;
}}
QTabBar::tab:selected {{ background-color: {DARK['accent']}; color: white; }}
QLabel#title {{
    font-size: 22px;
    font-weight: 700;
    color: {DARK['text']};
    letter-spacing: -0.5px;
}}
QLabel#subtitle {{
    font-size: 13px;
    color: {DARK['text2']};
}}
QLabel#status_ok   {{ color: {DARK['success']}; font-weight: 600; }}
QLabel#status_err  {{ color: {DARK['danger']};  font-weight: 600; }}
QLabel#status_busy {{ color: {DARK['warning']}; font-weight: 600; }}
QStatusBar {{ background-color: {DARK['bg2']}; color: {DARK['text2']}; border-top: 1px solid {DARK['border']}; }}
QScrollBar:vertical {{
    background: {DARK['bg3']};
    width: 8px;
    border-radius: 4px;
}}
QScrollBar::handle:vertical {{
    background: {DARK['border']};
    border-radius: 4px;
    min-height: 20px;
}}
QFrame#dropzone {{
    background-color: {DARK['bg3']};
    border: 2px dashed {DARK['border']};
    border-radius: 10px;
}}
QFrame#dropzone:hover {{ border-color: {DARK['accent']}; }}
QCheckBox {{
    color: {DARK['text']};
    spacing: 8px;
}}
QCheckBox::indicator {{
    width: 16px; height: 16px;
    border: 1px solid {DARK['border']};
    border-radius: 4px;
    background: {DARK['bg3']};
}}
QCheckBox::indicator:checked {{
    background: {DARK['accent']};
    border-color: {DARK['accent']};
}}
"""


# ─── Worker Threads ─────────────────────────────────────────────────────────────

class HealthWorker(QThread):
    result = pyqtSignal(dict)
    error  = pyqtSignal(str)

    def __init__(self, base_url: str):
        super().__init__()
        self.base_url = base_url

    def run(self):
        try:
            r = requests.get(f"{self.base_url}/health", timeout=5)
            r.raise_for_status()
            self.result.emit(r.json())
        except Exception as e:
            self.error.emit(str(e))


class UploadWorker(QThread):
    job_started = pyqtSignal(str)   # job_id
    error       = pyqtSignal(str)

    def __init__(self, base_url, video_path, params):
        super().__init__()
        self.base_url   = base_url
        self.video_path = video_path
        self.params     = params

    def run(self):
        try:
            with open(self.video_path, "rb") as f:
                r = requests.post(
                    f"{self.base_url}/process",
                    files={"file": (
                        Path(self.video_path).name,
                        f,
                        mimetypes.guess_type(self.video_path)[0] or "application/octet-stream",
                    )},
                    data=self.params,
                    timeout=(30, None),
                )
            r.raise_for_status()
            self.job_started.emit(r.json()["job_id"])
        except Exception as e:
            self.error.emit(str(e))


class PollWorker(QThread):
    status_update = pyqtSignal(dict)
    done          = pyqtSignal(str)   # job_id
    failed        = pyqtSignal(str)   # error message

    def __init__(self, base_url, job_id):
        super().__init__()
        self.base_url = base_url
        self.job_id   = job_id
        self._stop    = False

    def stop(self):
        self._stop = True

    def run(self):
        while not self._stop:
            try:
                r = requests.get(f"{self.base_url}/status/{self.job_id}", timeout=10)
                r.raise_for_status()
                data = r.json()
                self.status_update.emit(data)
                if data["status"] == "done":
                    self.done.emit(self.job_id)
                    return
                if data["status"] == "error":
                    self.failed.emit(data.get("error", "Unknown error"))
                    return
            except Exception as e:
                self.failed.emit(str(e))
                return
            time.sleep(3)


class DownloadWorker(QThread):
    progress = pyqtSignal(int)
    done     = pyqtSignal(str)   # saved path
    error    = pyqtSignal(str)

    def __init__(self, base_url, job_id, save_path):
        super().__init__()
        self.base_url  = base_url
        self.job_id    = job_id
        self.save_path = save_path

    def run(self):
        try:
            r = requests.get(
                f"{self.base_url}/download/{self.job_id}",
                stream=True, timeout=60
            )
            r.raise_for_status()
            total = int(r.headers.get("content-length", 0))
            received = 0
            with open(self.save_path, "wb") as f:
                for chunk in r.iter_content(chunk_size=1024 * 512):
                    f.write(chunk)
                    received += len(chunk)
                    if total:
                        self.progress.emit(int(received / total * 100))
            self.done.emit(self.save_path)
        except Exception as e:
            self.error.emit(str(e))


# ─── Drop Zone Widget ───────────────────────────────────────────────────────────

class DropZone(QFrame):
    file_dropped = pyqtSignal(str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setObjectName("dropzone")
        self.setAcceptDrops(True)
        self.setMinimumHeight(110)
        self.setCursor(Qt.CursorShape.PointingHandCursor)
        self._file = None

        layout = QVBoxLayout(self)
        layout.setAlignment(Qt.AlignmentFlag.AlignCenter)

        self.icon_label = QLabel("🎞")
        self.icon_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.icon_label.setStyleSheet("font-size: 32px; background: transparent;")

        self.text_label = QLabel("Drop VHS video here\nor click to browse")
        self.text_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.text_label.setStyleSheet(f"color: {DARK['text2']}; background: transparent; font-size: 13px;")

        self.file_label = QLabel("")
        self.file_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.file_label.setStyleSheet(f"color: {DARK['accent']}; background: transparent; font-size: 12px;")

        layout.addWidget(self.icon_label)
        layout.addWidget(self.text_label)
        layout.addWidget(self.file_label)

    def mousePressEvent(self, event):
        path, _ = QFileDialog.getOpenFileName(
            self, "Select VHS video", "",
            "Video files (*.mp4 *.mkv *.mov *.avi *.webm *.m4v *.wmv *.mpg *.mpeg *.mts *.m2ts *.ts *.vob *.flv *.3gp *.ogv);;All files (*)"
        )
        if path:
            self._set_file(path)

    def dragEnterEvent(self, event: QDragEnterEvent):
        if event.mimeData().hasUrls():
            event.acceptProposedAction()
            self.setStyleSheet(f"QFrame#dropzone {{ border-color: {DARK['accent']}; background: {DARK['bg2']}; border-radius: 10px; border: 2px dashed {DARK['accent']}; }}")

    def dragLeaveEvent(self, event):
        self.setStyleSheet("")

    def dropEvent(self, event: QDropEvent):
        self.setStyleSheet("")
        urls = event.mimeData().urls()
        if urls:
            path = urls[0].toLocalFile()
            if Path(path).suffix.lower() in {
                ".mp4", ".mkv", ".mov", ".avi", ".webm", ".m4v", ".wmv",
                ".mpg", ".mpeg", ".mts", ".m2ts", ".ts", ".vob", ".flv",
                ".3gp", ".ogv",
            }:
                self._set_file(path)

    def _set_file(self, path: str):
        self._file = path
        name = Path(path).name
        size = Path(path).stat().st_size / 1024 / 1024
        self.text_label.setText("Video selected ✓")
        self.file_label.setText(f"{name}  ({size:.1f} MB)")
        self.icon_label.setText("✅")
        self.file_dropped.emit(path)


# ─── Main Window ───────────────────────────────────────────────────────────────

class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.settings  = QSettings("VHSRestorer", "Client")
        self.job_id    = None
        self.poller    = None
        self.video_path = None

        self.setWindowTitle("VHS Restorer  ·  LTX2.3-ICEdit")
        self.setMinimumSize(860, 680)
        self.resize(
            self.settings.value("width",  960, int),
            self.settings.value("height", 720, int),
        )

        self._build_ui()
        self._apply_saved_settings()

    # ── UI Construction ──────────────────────────────────────────────────────

    def _build_ui(self):
        central = QWidget()
        self.setCentralWidget(central)
        root = QVBoxLayout(central)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        # Header bar
        header = QWidget()
        header.setFixedHeight(56)
        header.setStyleSheet(f"background: {DARK['bg2']}; border-bottom: 1px solid {DARK['border']};")
        hl = QHBoxLayout(header)
        hl.setContentsMargins(20, 0, 20, 0)

        title = QLabel("VHS Restorer")
        title.setObjectName("title")
        subtitle = QLabel("powered by LTX2.3-ICEdit-Insight")
        subtitle.setObjectName("subtitle")

        self.ffmpeg_label = QLabel("⬤  FFmpeg: checking…")
        self.ffmpeg_label.setStyleSheet(f"color: {DARK['text2']};")

        self.conn_label = QLabel("⬤  Not connected")
        self.conn_label.setStyleSheet(f"color: {DARK['text2']};")

        hl.addWidget(title)
        hl.addSpacing(12)
        hl.addWidget(subtitle)
        hl.addStretch()
        hl.addWidget(self.ffmpeg_label)
        hl.addSpacing(20)
        hl.addWidget(self.conn_label)
        root.addWidget(header)

        # Main content
        content = QWidget()
        content_layout = QHBoxLayout(content)
        content_layout.setContentsMargins(16, 16, 16, 16)
        content_layout.setSpacing(12)

        # ── Left panel ────────────────────────────────────────────────────────
        left = QWidget()
        left.setFixedWidth(320)
        left_layout = QVBoxLayout(left)
        left_layout.setContentsMargins(0, 0, 0, 0)
        left_layout.setSpacing(10)

        # Server settings
        server_group = QGroupBox("Server")
        sg = QVBoxLayout(server_group)

        url_row = QHBoxLayout()
        url_row.addWidget(QLabel("URL:"))
        self.url_input = QLineEdit("http://localhost:8000")
        self.url_input.setPlaceholderText("https://xxxx-8000.proxy.runpod.net")
        url_row.addWidget(self.url_input)
        sg.addLayout(url_row)

        btn_row = QHBoxLayout()
        self.btn_connect = QPushButton("Connect")
        self.btn_connect.setObjectName("primary")
        self.btn_connect.clicked.connect(self.check_health)
        btn_row.addWidget(self.btn_connect)

        self.btn_save_url = QPushButton("Save")
        self.btn_save_url.clicked.connect(self.save_url)
        btn_row.addWidget(self.btn_save_url)
        sg.addLayout(btn_row)

        self.health_text = QLabel("GPU: —\nVRAM: —")
        self.health_text.setStyleSheet(f"color: {DARK['text2']}; font-size: 12px;")
        sg.addWidget(self.health_text)
        left_layout.addWidget(server_group)

        # Video input
        video_group = QGroupBox("Input Video")
        vg = QVBoxLayout(video_group)
        self.drop_zone = DropZone()
        self.drop_zone.file_dropped.connect(self._on_file_selected)
        vg.addWidget(self.drop_zone)
        left_layout.addWidget(video_group)

        # Processing options
        opts_group = QGroupBox("Processing Options")
        og = QGridLayout(opts_group)
        og.setSpacing(8)

        og.addWidget(QLabel("Mode:"), 0, 0)
        self.mode_combo = QComboBox()
        self.mode_combo.addItems([
            "restoration — VHS artifact removal",
            "hd — HD upscale only",
            "both — Restore → HD upscale",
        ])
        self.mode_combo.setCurrentIndex(2)
        og.addWidget(self.mode_combo, 0, 1)

        og.addWidget(QLabel("Resolution:"), 1, 0)
        res_row = QHBoxLayout()
        self.width_spin = QSpinBox()
        self.width_spin.setRange(256, 1024)
        self.width_spin.setSingleStep(32)
        self.width_spin.setValue(352)
        self.height_spin = QSpinBox()
        self.height_spin.setRange(256, 1024)
        self.height_spin.setSingleStep(32)
        self.height_spin.setValue(512)
        res_row.addWidget(self.width_spin)
        res_row.addWidget(QLabel("×"))
        res_row.addWidget(self.height_spin)
        res_widget = QWidget()
        res_widget.setLayout(res_row)
        og.addWidget(res_widget, 1, 1)

        og.addWidget(QLabel("Frames (8k+1):"), 2, 0)
        self.frames_combo = QComboBox()
        self.frames_combo.addItems(["25 (~1s)", "49 (~2s)", "97 (~4s)", "145 (~6s)", "217 (~9s)"])
        self.frames_combo.setCurrentIndex(2)
        og.addWidget(self.frames_combo, 2, 1)

        og.addWidget(QLabel("FPS:"), 3, 0)
        self.fps_spin = QDoubleSpinBox()
        self.fps_spin.setRange(1, 60)
        self.fps_spin.setValue(24.0)
        self.fps_spin.setSingleStep(1)
        og.addWidget(self.fps_spin, 3, 1)

        og.addWidget(QLabel("Seed:"), 4, 0)
        self.seed_spin = QSpinBox()
        self.seed_spin.setRange(0, 99999)
        self.seed_spin.setValue(42)
        og.addWidget(self.seed_spin, 4, 1)

        left_layout.addWidget(opts_group)
        left_layout.addStretch()

        # ── Right panel ───────────────────────────────────────────────────────
        right = QWidget()
        right_layout = QVBoxLayout(right)
        right_layout.setContentsMargins(0, 0, 0, 0)
        right_layout.setSpacing(10)

        # Job control
        ctrl_group = QGroupBox("Job Control")
        cg = QVBoxLayout(ctrl_group)

        btn_bar = QHBoxLayout()
        self.btn_process = QPushButton("▶  Start Processing")
        self.btn_process.setObjectName("primary")
        self.btn_process.setMinimumHeight(40)
        self.btn_process.clicked.connect(self.start_job)
        btn_bar.addWidget(self.btn_process)

        self.btn_download = QPushButton("⬇  Download Result")
        self.btn_download.setObjectName("success")
        self.btn_download.setMinimumHeight(40)
        self.btn_download.clicked.connect(self.download_result)
        self.btn_download.setEnabled(False)
        btn_bar.addWidget(self.btn_download)
        cg.addLayout(btn_bar)

        # Progress
        prog_row = QHBoxLayout()
        self.progress_bar = QProgressBar()
        self.progress_bar.setValue(0)
        prog_row.addWidget(self.progress_bar)
        self.pct_label = QLabel("0%")
        self.pct_label.setFixedWidth(36)
        self.pct_label.setStyleSheet(f"color: {DARK['text2']};")
        prog_row.addWidget(self.pct_label)
        cg.addLayout(prog_row)

        status_row = QHBoxLayout()
        self.status_icon = QLabel("○")
        self.status_icon.setFixedWidth(16)
        self.job_status_label = QLabel("No active job")
        self.job_status_label.setStyleSheet(f"color: {DARK['text2']};")
        self.elapsed_label = QLabel("")
        self.elapsed_label.setStyleSheet(f"color: {DARK['text2']}; font-size: 11px;")
        status_row.addWidget(self.status_icon)
        status_row.addWidget(self.job_status_label)
        status_row.addStretch()
        status_row.addWidget(self.elapsed_label)
        cg.addLayout(status_row)

        self.job_id_label = QLabel("Job ID: —")
        self.job_id_label.setStyleSheet(f"color: {DARK['text2']}; font-size: 11px; font-family: monospace;")
        cg.addWidget(self.job_id_label)

        right_layout.addWidget(ctrl_group)

        # Log output
        log_group = QGroupBox("Server Log")
        lg = QVBoxLayout(log_group)
        self.log_text = QTextEdit()
        self.log_text.setReadOnly(True)
        self.log_text.setMinimumHeight(200)
        lg.addWidget(self.log_text)

        log_btn_row = QHBoxLayout()
        btn_clear = QPushButton("Clear")
        btn_clear.clicked.connect(self.log_text.clear)
        log_btn_row.addStretch()
        log_btn_row.addWidget(btn_clear)
        lg.addLayout(log_btn_row)
        right_layout.addWidget(log_group)

        # Tips
        tips_group = QGroupBox("VHS Tips")
        tg = QVBoxLayout(tips_group)
        tips = QLabel(
            "• Resolution 352×512 = fastest (~14 GB VRAM)\n"
            "• Resolution 704×1024 = best quality (~17 GB)\n"
            "• Mode 'both' = 2× slower but best VHS results\n"
            "• Frames=97 ≈ 4s clip at 24fps\n"
            "• Split long videos into 4-second chunks first"
        )
        tips.setStyleSheet(f"color: {DARK['text2']}; font-size: 12px; line-height: 1.8;")
        tips.setWordWrap(True)
        tg.addWidget(tips)
        right_layout.addWidget(tips_group)

        content_layout.addWidget(left)
        content_layout.addWidget(right)
        root.addWidget(content)

        # Status bar
        self.statusbar = QStatusBar()
        self.setStatusBar(self.statusbar)
        self.statusbar.showMessage("Ready — connect to your RunPod server to begin")

    # ── Logic ────────────────────────────────────────────────────────────────

    def _apply_saved_settings(self):
        saved_url = self.settings.value("server_url", "")
        if saved_url:
            self.url_input.setText(saved_url)

        # Check if ffmpeg is available locally
        import shutil
        if shutil.which("ffmpeg"):
            self._log("[system] ffmpeg found locally ✓")
            self.ffmpeg_label.setText("⬤  FFmpeg: installed")
            self.ffmpeg_label.setStyleSheet(f"color: {DARK['success']};")
            self.ffmpeg_label.setToolTip("FFmpeg is available locally. You can split and merge videos.")
        else:
            self._log("[system] WARNING: ffmpeg not found locally. You will need it to split/merge long videos.")
            self.ffmpeg_label.setText("⬤  FFmpeg: not found")
            self.ffmpeg_label.setStyleSheet(f"color: {DARK['danger']};")
            self.ffmpeg_label.setToolTip("FFmpeg is NOT found locally. You will not be able to split/merge long videos.")

    def save_url(self):
        self.settings.setValue("server_url", self.url_input.text().strip())
        self.statusbar.showMessage("URL saved")

    def save_geometry_settings(self):
        self.settings.setValue("width",  self.width())
        self.settings.setValue("height", self.height())

    def closeEvent(self, event):
        self.save_geometry_settings()
        if self.poller:
            self.poller.stop()
        super().closeEvent(event)

    def _base_url(self) -> str:
        return self.url_input.text().strip().rstrip("/")

    def check_health(self):
        self.btn_connect.setEnabled(False)
        self.btn_connect.setText("Checking...")
        self.conn_label.setText("⬤  Connecting…")
        self.conn_label.setStyleSheet(f"color: {DARK['warning']};")

        self._health_worker = HealthWorker(self._base_url())
        self._health_worker.result.connect(self._on_health_ok)
        self._health_worker.error.connect(self._on_health_err)
        self._health_worker.start()

    def _on_health_ok(self, data: dict):
        self.btn_connect.setEnabled(True)
        self.btn_connect.setText("Re-check")
        self.conn_label.setText("⬤  Connected")
        self.conn_label.setStyleSheet(f"color: {DARK['success']}; font-weight: 600;")

        gpu = data.get("gpu", {})
        name = gpu.get("name", "Unknown GPU")
        total = gpu.get("vram_total_gb", "?")
        free  = gpu.get("vram_free_gb", "?")
        ready = "✓" if data.get("models_ready") else "✗ (models not found!)"
        self.health_text.setText(
            f"GPU: {name}\nVRAM: {free} GB free / {total} GB total\nModels: {ready}"
        )
        self.statusbar.showMessage(f"Connected to {self._base_url()}")
        self._log(f"[health] GPU={name}  VRAM={free}/{total}GB  models={ready}")

    def _on_health_err(self, err: str):
        self.btn_connect.setEnabled(True)
        self.btn_connect.setText("Connect")
        self.conn_label.setText("⬤  Connection failed")
        self.conn_label.setStyleSheet(f"color: {DARK['danger']};")
        self.health_text.setText(f"Error: {err}")
        self.statusbar.showMessage(f"Connection failed: {err}")
        self._log(f"[error] {err}")

    def _on_file_selected(self, path: str):
        self.video_path = path
        self.statusbar.showMessage(f"Selected: {Path(path).name}")
        self._log(f"[file] {path}")
        
        # Автоматическое определение параметров видео через ffprobe
        import subprocess
        import json
        import shutil
        
        if shutil.which("ffprobe"):
            try:
                cmd = [
                    "ffprobe", "-v", "error", "-select_streams", "v:0",
                    "-show_entries", "stream=width,height,r_frame_rate", 
                    "-of", "json", path
                ]
                res = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
                if res.returncode == 0:
                    info = json.loads(res.stdout)
                    if "streams" in info and len(info["streams"]) > 0:
                        stream = info["streams"][0]
                        w = stream.get("width")
                        h = stream.get("height")
                        fps_raw = stream.get("r_frame_rate", "24/1")
                        
                        if w and h:
                            # Округляем до ближайшего кратного 16 (рекомендуется для LTX моделей)
                            w_rounded = max(256, min(1024, round(w / 16) * 16))
                            h_rounded = max(256, min(1024, round(h / 16) * 16))
                            
                            self.width_spin.setValue(w_rounded)
                            self.height_spin.setValue(h_rounded)
                            
                            log_msg = f"[info] Probed resolution: {w}x{h} -> set to {w_rounded}x{h_rounded}"
                            
                            # Попробуем прочитать FPS
                            if "/" in fps_raw:
                                try:
                                    num, den = map(int, fps_raw.split("/"))
                                    if den > 0:
                                        fps = round(num / den, 2)
                                        self.fps_spin.setValue(fps)
                                        log_msg += f", FPS: {fps}"
                                except Exception:
                                    pass
                            
                            self._log(log_msg)
                            self.statusbar.showMessage(f"Selected: {Path(path).name} ({w}x{h})")
            except Exception as e:
                self._log(f"[system] Failed to probe video: {e}")

    def _get_mode(self) -> str:
        idx = self.mode_combo.currentIndex()
        return ["restoration", "hd", "both"][idx]

    def _get_frames(self) -> int:
        text = self.frames_combo.currentText()
        return int(text.split()[0])

    def start_job(self):
        if not self.video_path:
            QMessageBox.warning(self, "No video", "Please select a VHS video file first.")
            return

        params = {
            "mode":       self._get_mode(),
            "height":     str(self.height_spin.value()),
            "width":      str(self.width_spin.value()),
            "num_frames": str(self._get_frames()),
            "fps":        str(self.fps_spin.value()),
            "seed":       str(self.seed_spin.value()),
        }

        self.btn_process.setEnabled(False)
        self.btn_download.setEnabled(False)
        self.progress_bar.setValue(0)
        self.pct_label.setText("0%")
        self._set_status("Uploading video…", DARK["warning"])
        self._log(f"[upload] {Path(self.video_path).name}  params={params}")

        self._upload_worker = UploadWorker(self._base_url(), self.video_path, params)
        self._upload_worker.job_started.connect(self._on_job_started)
        self._upload_worker.error.connect(self._on_job_error)
        self._upload_worker.start()

    def _on_job_started(self, job_id: str):
        self.job_id = job_id
        self.job_id_label.setText(f"Job ID: {job_id}")
        self._set_status("Queued on server…", DARK["info"])
        self._log(f"[job] started  id={job_id}")

        self.poller = PollWorker(self._base_url(), job_id)
        self.poller.status_update.connect(self._on_status_update)
        self.poller.done.connect(self._on_job_done)
        self.poller.failed.connect(self._on_job_error)
        self.poller.start()

    def _on_status_update(self, data: dict):
        pct = data.get("progress", 0)
        status = data.get("status", "")
        elapsed = data.get("elapsed", 0)

        self.progress_bar.setValue(pct)
        self.pct_label.setText(f"{pct}%")
        self.elapsed_label.setText(f"{elapsed:.0f}s")

        status_map = {
            "queued":       ("Queued…",               DARK["info"]),
            "preprocessing":("Preprocessing video…",  DARK["warning"]),
            "restoring":    ("Restoring VHS…",         DARK["accent"]),
            "upscaling":    ("HD upscaling…",          DARK["accent"]),
            "processing":   ("Processing…",            DARK["accent"]),
            "done":         ("Done!",                  DARK["success"]),
            "error":        ("Error!",                 DARK["danger"]),
        }
        label, color = status_map.get(status, (status, DARK["text2"]))
        self._set_status(label, color)

        log_lines = data.get("log", [])
        if log_lines:
            self._log("\n".join(log_lines[-5:]))

    def _on_job_done(self, job_id: str):
        if self.poller:
            self.poller.stop()
        self.progress_bar.setValue(100)
        self.pct_label.setText("100%")
        self._set_status("✓  Processing complete!", DARK["success"])
        self.btn_download.setEnabled(True)
        self.btn_process.setEnabled(True)
        self._log(f"[done] job={job_id}")
        self.statusbar.showMessage("Processing complete — download your result!")

    def _on_job_error(self, err: str):
        if self.poller:
            self.poller.stop()
        self._set_status(f"Error: {err}", DARK["danger"])
        self.btn_process.setEnabled(True)
        self._log(f"[error] {err}")
        self.statusbar.showMessage(f"Error: {err}")

    def download_result(self):
        if not self.job_id:
            return
        save_path, _ = QFileDialog.getSaveFileName(
            self, "Save restored video", f"restored_{self.job_id}.mp4",
            "MP4 video (*.mp4)"
        )
        if not save_path:
            return

        self.btn_download.setEnabled(False)
        self._set_status("Downloading…", DARK["info"])
        self._log(f"[download] saving to {save_path}")

        self._dl_worker = DownloadWorker(self._base_url(), self.job_id, save_path)
        self._dl_worker.progress.connect(lambda p: self.progress_bar.setValue(p))
        self._dl_worker.done.connect(self._on_download_done)
        self._dl_worker.error.connect(self._on_job_error)
        self._dl_worker.start()

    def _on_download_done(self, path: str):
        self._set_status("✓  Saved!", DARK["success"])
        self.statusbar.showMessage(f"Saved: {path}")
        self._log(f"[saved] {path}")
        self.btn_download.setEnabled(True)
        QMessageBox.information(self, "Done", f"Video saved to:\n{path}")

    def _set_status(self, text: str, color: str):
        self.job_status_label.setText(text)
        self.job_status_label.setStyleSheet(f"color: {color}; font-weight: 500;")

    def _log(self, text: str):
        self.log_text.append(text)
        sb = self.log_text.verticalScrollBar()
        sb.setValue(sb.maximum())


# ─── Entry point ───────────────────────────────────────────────────────────────

def main():
    app = QApplication(sys.argv)
    app.setStyleSheet(STYLESHEET)
    app.setApplicationName("VHS Restorer")
    app.setOrganizationName("VHSRestorer")

    window = MainWindow()
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
