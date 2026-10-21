"""The whole menu offscreen (Harness.qml): staging, fixtures, typing.

Used by tests/typing_cost.py. Needs PySide6, the installed Omarchy shell's
qs.Commons and qs.Ui (OMARCHY_SHELL, default /usr/share/omarchy/shell) and
its menu file (OMARCHY_PATH, default /usr/share/omarchy);
Quickshell itself is stood in for by imports/.
"""
import json
import os
import re
import shutil
import sys
import time

os.environ["QT_QPA_PLATFORM"] = "offscreen"
os.environ["QT_QPA_PLATFORMTHEME"] = "generic"
os.environ.pop("QT_SCALE_FACTOR", None)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SHELL = os.environ.get("OMARCHY_SHELL", "/usr/share/omarchy/shell")
# The System menu searched: the installed Omarchy's own.
MENU_FILE = os.path.join(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"), "default/omarchy/omarchy-menu.jsonc")

from PySide6.QtCore import QUrl, Qt, QEvent  # noqa: E402
from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtQml import QQmlEngine, QQmlComponent  # noqa: E402
from PySide6.QtQuick import QQuickItem, QQuickWindow  # noqa: E402,F401  (converters)
from PySide6.QtTest import QTest  # noqa: E402

if any(a.startswith("-qmljsdebugger") for a in sys.argv):
    from PySide6.QtQml import QQmlDebuggingEnabler
    QQmlDebuggingEnabler.enableDebugging(True)
APP = QGuiApplication.instance() or QGuiApplication(sys.argv)


def stage_plugin(dst, src=ROOT):
    """A copy of the plugin to load: its QML and JS, minus what only a
    compositor has (layer-shell attached properties), with a steady text
    cursor, the harness, and an import dir pointing at the shell's modules."""
    shutil.rmtree(dst, ignore_errors=True)
    os.makedirs(dst)
    for name in os.listdir(src):
        p = os.path.join(src, name)
        if name.endswith((".qml", ".js")) and os.path.isfile(p):
            shutil.copy2(p, dst)
    shutil.copytree(os.path.join(src, "ai"), os.path.join(dst, "ai"))
    menu = os.path.join(dst, "Menu.qml")
    text = re.sub(r"^\s*WlrLayershell\.[a-zA-Z]+:.*$", "", open(menu).read(), flags=re.M)
    open(menu, "w").write(text)
    blink = os.path.join(dst, "CursorBlink.qml")
    steady = re.sub(r"interval:\s*\d+", "interval: 100000000", open(blink).read())
    open(blink, "w").write(steady)
    shutil.copy2(os.path.join(HERE, "Harness.qml"), dst)
    imports = os.path.join(dst, "_imports")
    shutil.copytree(os.path.join(HERE, "imports"), imports)
    os.makedirs(os.path.join(imports, "qs"))
    for mod in ("Commons", "Ui"):
        os.symlink(os.path.join(SHELL, mod), os.path.join(imports, "qs", mod))
    return dst


def fake_apps():
    names = ["Firefox", "Alacritty", "Files", "Obsidian", "Signal", "Spotify", "Typora", "Visual Studio Code", "Neovim",
             "Chromium", "LibreOffice Writer", "LibreOffice Calc", "GIMP", "Inkscape", "Kdenlive", "OBS Studio", "Pinta",
             "Xournal++", "Zoom", "1Password", "Docker Desktop", "Basecamp", "HEY", "WhatsApp", "Google Photos",
             "Google Contacts", "Google Messages", "X", "YouTube", "Discord", "ChatGPT", "Figma", "GitHub", "Omarchy Manual",
             "About", "Activity", "Bluetooth", "Wi-Fi", "Audio", "Disk Usage", "Calculator", "Image Viewer", "Media Player",
             "Document Viewer", "Fcitx 5", "Terminal", "Btop", "LazyDocker", "Firewall Settings", "Fireworks Demo",
             "Foxit Reader", "Thunderbird", "Steam", "Kitty", "Ghostty", "Fonts", "Archive Manager", "Screen Recorder",
             "Color Picker", "Printers"]
    out = []
    for i, n in enumerate(names):
        slug = re.sub(r"[^a-z0-9]+", "-", n.lower()).strip("-")
        out.append({"id": slug, "name": n, "genericName": "Application" if i % 3 else "", "icon": slug,
                    "noDisplay": False, "keywords": [], "comment": ""})
    return out


def fake_files():
    dirs = ["Documents", "Documents/notes", "Downloads", "Pictures", "Pictures/wallpapers", "src", "src/omarchy",
            "src/firefox-tweaks", ".config", ".config/firefox", ".mozilla/firefox/abc.default-release", "Videos", "Music",
            "go/pkg/mod/github.com/fire", "work/firebase-app", "work/firebase-app/src", "Desktop"]
    stems = ["firefox", "firewall", "fireworks", "fire-notes", "campfire", "firebase", "fire-up", "wildfire", "firefly",
             "fire drill", "fireplace", "firestore", "foxfire", "bonfire", "spitfire", "firefox-nightly", "fireball",
             "surefire", "report", "notes", "todo", "budget", "photo", "invoice", "readme", "config", "main", "index",
             "terminal", "theme", "term-paper", "fox", "fig", "final", "first", "fiscal", "filter"]
    exts = [".md", ".txt", ".png", ".pdf", ".json", ".sh", ".js", ".py", ".go", ".svg"]
    files, folders = [], []
    for d in dirs:
        folders.append(d)
        for i, s in enumerate(stems):
            files.append("%s/%s%s" % (d, s, exts[(i + len(d)) % len(exts)]))
    for s in stems[:12]:
        folders.append("Documents/" + s)
    return files, folders


def fake_clients():
    apps = [("firefox", "Mozilla Firefox — Fire safety tips"), ("Alacritty", "~/src/omarchy-menu"), ("obsidian", "notes — Obsidian"),
            ("signal", "Signal"), ("Alacritty", "btop")]
    return [{"address": "0xaaab1310%04x" % i, "class": c, "initialClass": c, "title": t,
             "workspace": {"id": 1 + i % 3, "name": str(1 + i % 3)}, "mapped": True, "hidden": False,
             "focusHistoryID": i, "pid": 1000 + i} for i, (c, t) in enumerate(apps)]


class Stage:
    """One menu, loaded and opened with style.json's "look" set to `look`."""

    def __init__(self, plugin_dir, look="classic", home="/home/typing"):
        files, folders = fake_files()
        menu_file = MENU_FILE
        rules = [
            {"match": "default/omarchy/omarchy-menu.jsonc", "out": open(menu_file).read()},
            {"match": "extensions/omarchy-menu.jsonc", "out": "", "code": 1},
            {"match": "launcher.hides", "out": ""},
            {"match": "style.json", "out": json.dumps({"look": look})},
            {"match": "state.json", "out": "{}"},
        ]
        fixtures = {"env": {"HOME": home, "OMARCHY_PATH": "/usr/share/omarchy"}, "apps": fake_apps(), "rules": rules,
                    "files": files, "folders": folders, "home": home, "clients": fake_clients()}
        self.engine = QQmlEngine()
        self.engine.addImportPath(os.path.join(plugin_dir, "_imports"))
        self.engine.rootContext().setContextProperty("harnessFixtures", json.dumps(fixtures))
        self.component = QQmlComponent(self.engine, QUrl.fromLocalFile(os.path.join(plugin_dir, "Harness.qml")))
        self.root = self.component.create()
        if self.root is None:
            raise RuntimeError("\n".join(e.toString() for e in self.component.errors()))
        self.menu = self.root.property("menu")
        self.pump(300)
        self.win = None

    def pump(self, ms):
        end = time.perf_counter() + ms / 1000.0
        while True:
            APP.processEvents()
            left = end - time.perf_counter()
            if left <= 0:
                break
            time.sleep(min(0.002, left))

    def open(self, payload="{}"):
        self.menu.open(payload)
        self.pump(400)
        if self.win is None:
            self.win = [w for w in APP.topLevelWindows() if isinstance(w, QQuickWindow)][-1]
        self.win.show()
        self.win.resize(1440, 900)
        self.win.requestActivate()
        self.pump(300)

    def key(self, ch, settle_ms):
        if ch == "\b":
            QTest.keyClick(self.win, Qt.Key.Key_Backspace)
        elif len(ch) == 1:
            QTest.keyClick(self.win, ch)
        else:
            QTest.keyClick(self.win, getattr(Qt.Key, "Key_" + ch))
        self.pump(settle_ms)
