#!/usr/bin/env python3
"""Typing cost per look, counted: a regression guard.

Each look types "firefox" into All with the whole menu offscreen (the real
Menu.qml and look files, Quickshell stood in for by tests/typing/), recorded
by qmlprofiler. What is checked are counts, not times: how often bindings
ran and how many objects were made. They do not depend on how busy the
machine is, so a change that makes a keystroke do more shows up at once.
The ceilings are the measured values with headroom (animations add a few
frame-timed evaluations); lower them when a change makes typing cheaper.

Skips (exit 0) without PySide6, qmlprofiler (QMLPROFILER, default
/usr/lib/qt6/bin/qmlprofiler), the Omarchy shell's qs modules
(OMARCHY_SHELL, default /usr/share/omarchy/shell) or Omarchy's menu file
(OMARCHY_PATH, default /usr/share/omarchy). About a minute per look.

Run with: python3 tests/typing_cost.py [--report] [look ...]
"""
import os
import socket
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TYPING = os.path.join(HERE, "typing")
QMLPROFILER = os.environ.get("QMLPROFILER", "/usr/lib/qt6/bin/qmlprofiler")
SHELL = os.environ.get("OMARCHY_SHELL", "/usr/share/omarchy/shell")

# Per look: (what, ceiling). "bind:<file>" counts binding evaluations in that
# file, "bind:<file>:<property>" one property's, "call:<file>:<function>"
# calls, "created" objects made. Measured values are in the comments.
CEILINGS = {
    "classic": [("bind:Menu.qml", 740),           # 654 (984 before the list/count fixes)
                ("bind:TabBar.qml", 700),         # 617 (831 when every rebuild made new counts)
                ("bind:ResultRow.qml", 2550),     # 2276
                ("created", 570)],                # 508
    "mala": [("bind:Menu.qml", 530),              # 464
             ("bind:MalaRow.qml", 1600),          # 1406
             ("created", 260)],                   # 223
}
# What every look shares: the card's height walks the rows once per rebuild
# (28; 274 when it read every row through the model).
COMMON = [("bind:Menu.qml:desiredRowsHeight", 45)]


def missing():
    try:
        import PySide6  # noqa: F401
    except ImportError:
        return "PySide6"
    if not os.access(QMLPROFILER, os.X_OK):
        return QMLPROFILER
    for mod in ("Commons", "Ui"):
        if not os.path.isdir(os.path.join(SHELL, mod)):
            return os.path.join(SHELL, mod)
    menu = os.path.join(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"), "default/omarchy/omarchy-menu.jsonc")
    if not os.path.exists(menu):
        return menu
    return None


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def measure(stage_dir, look, out_dir):
    sys.path.insert(0, TYPING)
    from profile import counts
    port = free_port()
    log = open(os.path.join(out_dir, look + ".log"), "w+")
    child = subprocess.Popen([sys.executable, os.path.join(TYPING, "run.py"), stage_dir, look,
                              "-qmljsdebugger=port:%d,block" % port], stdout=log, stderr=subprocess.STDOUT)
    for _ in range(100):
        log.flush(); log.seek(0)
        if "Waiting for connection" in log.read():
            break
        time.sleep(0.1)
    trace = os.path.join(out_dir, look + ".qtd")
    subprocess.run([QMLPROFILER, "--record", "off", "--exclude", "memory,pixmapcache,scenegraph,animations",
                    "--attach", "127.0.0.1", "--port", str(port), "-o", trace],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=180)
    child.wait(timeout=60)
    if not os.path.exists(trace):
        log.seek(0)
        raise RuntimeError("no trace for %s:\n%s" % (look, log.read()[-2000:]))
    return counts(trace)


def main(argv):
    report = "--report" in argv
    looks = [a for a in argv if not a.startswith("--")] or list(CEILINGS)
    why = missing()
    if why:
        print("typing cost: skipped (missing %s)" % why)
        return 0
    sys.path.insert(0, TYPING)
    from stage import stage_plugin
    tmp = tempfile.mkdtemp(prefix="typing-cost-")
    stage_dir = stage_plugin(os.path.join(tmp, "plugin"))
    failures = []
    for look in looks:
        c = measure(stage_dir, look, tmp)
        if report:
            keys = sorted(k for k in c if k.count(":") <= 1)
            print("== %s: created %d" % (look, c["created"]))
            for k in keys:
                if k != "created":
                    print("   %-40s %d" % (k, c[k]))
            for k, n in sorted(((k, n) for k, n in c.items() if k.count(":") == 2), key=lambda kv: -kv[1])[:25]:
                print("   %-60s %d" % (k, n))
        for what, ceiling in COMMON + CEILINGS[look]:
            got = c.get(what, 0)
            status = "ok" if got <= ceiling else "OVER"
            print("%-10s %-58s %6d <= %6d %s" % (look, what, got, ceiling, status))
            if got > ceiling:
                failures.append("%s: %s ran %d times, ceiling %d" % (look, what, got, ceiling))
    if failures:
        print("FAILED\n  " + "\n  ".join(failures) + "\n(traces in %s)" % tmp)
        return 1
    print("OK")
    if not os.environ.get("KEEP"):
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
