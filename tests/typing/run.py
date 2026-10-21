"""One look, typed under qmlprofiler: run.py STAGE_DIR LOOK [-qmljsdebugger=...]

Opens the menu, settles, then records while TEXT is typed into All, one key
every GAP ms (env TEXT, GAP)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from stage import Stage, APP  # noqa: E402

stage_dir, look = sys.argv[1], sys.argv[2]
text = os.environ.get("TEXT", "firefox")
gap = int(os.environ.get("GAP", "350"))
s = Stage(stage_dir, look=look)
s.open()
s.key("x", gap)        # the first search builds what later ones reuse
s.key("\b", gap)
s.pump(800)
s.root.profileStart()
for ch in text:
    s.key(ch, gap)
s.root.profileStop()
s.pump(300)
APP.quit()
