#!/usr/bin/env python3
"""Exercise the shipped cursor and geometry components in the real Qt engine."""
import os
from pathlib import Path
import re
import unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QPA_PLATFORMTHEME", "generic")

from PySide6.QtCore import QEvent, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QJSEngine, QQmlComponent, QQmlEngine
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
APP = QGuiApplication([])


class QtRegressionTests(unittest.TestCase):
    def setUp(self):
        self.engine = QQmlEngine()
        self.components = []
        self.objects = []

    def tearDown(self):
        # Objects first, then the components and engine that own their types.
        for obj in self.objects:
            obj.deleteLater()
        APP.sendPostedEvents(None, QEvent.DeferredDelete)
        APP.processEvents()
        self.objects = []
        self.components = []
        self.engine.deleteLater()
        APP.sendPostedEvents(None, QEvent.DeferredDelete)
        self.engine = None

    def component(self, filename):
        c = QQmlComponent(self.engine, QUrl.fromLocalFile(str(ROOT / filename)))
        self.assertFalse(c.isError(), [e.toString() for e in c.errors()])
        self.components.append(c)
        obj = c.create()
        self.assertIsNotNone(obj, [e.toString() for e in c.errors()])
        QQmlEngine.setObjectOwnership(obj, QQmlEngine.CppOwnership)
        self.objects.append(obj)
        return obj

    def test_cursor_visibility_and_disabled_blinking(self):
        blink = self.component("CursorBlink.qml")
        blink.setProperty("interval", 10)
        for _ in range(5):
            blink.pulse()
        self.assertFalse(blink.property("running"))
        blink.setProperty("active", True)
        self.assertTrue(blink.property("running"))
        QTest.qWait(25)
        blink.pulse()
        self.assertTrue(blink.property("on"))
        blink.setProperty("active", False)
        blink.pulse()
        QTest.qWait(25)
        self.assertFalse(blink.property("running"))
        self.assertTrue(blink.property("on"))

    def test_system_search_commits_destination_once(self):
        source = (ROOT / "Menu.qml").read_text()
        functions = [
            re.search(r"^  function " + name + r"\([^)]*\) \{.*?^  \}", source, re.M | re.S).group()
            for name in ("rebuildForQuery", "jumpToSystemMatch")
        ]
        engine = QJSEngine()
        result = engine.evaluate("\n".join(functions) + """
            var activeRows = [];
            var displayModel = { get count() { return activeRows.length }, get: i => activeRows[i] };
            var entries = {
                capture: { id: "capture", parent: "root", kind: "menu" },
                screenshot: { id: "screenshot", parent: "capture", kind: "action" }
            };
            var hit = "", rebuilds = 0;
            var root = {
                activeMenu: "root", systemTwoPane: true,
                updateSystemMatches() { this.systemMatches = hit ? [hit] : []; },
                item: id => entries[id],
                rebuildDisplay() {
                    rebuilds++;
                    activeRows = this.activeMenu === "capture"
                        ? [{ itemId: "other" }, { itemId: "screenshot" }] : [];
                },
                syncSystemCategoryTo(id) {}, syncSystemCategory() {}, revealCursor() {},
                jumpToSystemMatch
            };
            function query(id) {
                hit = id;
                rebuilds = 0;
                rebuildForQuery();
                return [rebuilds, root.activeMenu, root.systemPane, root.selectedIndex];
            }
            var category = query("capture");
            var nested = query("screenshot");
            var immediateTarget = displayModel.get(root.selectedIndex).itemId;
            var missing = query("removed");
            var empty = query("");
            JSON.stringify([category, nested, immediateTarget, missing[0], empty[0]]);
        """)
        self.assertFalse(result.isError(), result.toString())
        self.assertEqual(result.toString(),
                         '[[1,"capture","left",0],[1,"capture","right",1],"screenshot",1,1]')

    def test_geometry_matrix(self):
        g = self.component("MenuGeometry.qml")
        scenarios = 0
        for height in [720, 1080, 1440]:
            for scale in [1, 1.5, 2]:
                for chrome in [100 * scale, 250 * scale, 1000 * scale]:
                    for top in [-1, height * .2, height * .9]:
                        for body in [0, height * .6]:
                            with self.subTest(height=height, scale=scale, chrome=chrome, top=top, body=body):
                                for key, value in dict(viewportHeight=height, gap=10, requestedTop=top,
                                                       chromeHeight=chrome, desiredBodyHeight=body,
                                                       minimumBodyHeight=150 * scale).items():
                                    g.setProperty(key, value)
                                self.assertGreaterEqual(g.property("cardTop"), 10)
                                self.assertLessEqual(g.property("cardTop") + g.property("cardHeight"), height - 10 + .01)
                                self.assertGreaterEqual(g.property("bodyHeight"), min(body, 150 * scale))
                                self.assertAlmostEqual(g.property("contentHeight"), chrome + g.property("bodyHeight"))
                                scenarios += 1
        self.assertEqual(scenarios, 162)

    def geometry(self, **values):
        g = self.component("MenuGeometry.qml")
        for key, value in values.items():
            g.setProperty(key, value)
        return g

    def test_low_top_keeps_footer_and_usable_results(self):
        # HDMI-A-1: 2304 logical px, top 0.9 / 0.6, body 0.95, fixed height.
        height, gap, chrome, footer, minimum = 2304, 10, 180, 22, 240
        for top in (0.6, 0.9):
            with self.subTest(top=top):
                g = self.geometry(viewportHeight=height, gap=gap, requestedTop=height * top, chromeHeight=chrome,
                                  desiredBodyHeight=height * .95, minimumBodyHeight=minimum, reserveHeight=8 + footer)
                self.assertGreaterEqual(g.property("bodyHeight"), minimum)
                self.assertAlmostEqual(g.property("cardTop") + g.property("cardHeight"), height - gap)
                self.assertAlmostEqual(g.property("contentHeight"), g.property("cardHeight"))

    def test_requested_top_unchanged_when_card_fits(self):
        g = self.geometry(viewportHeight=2304, gap=10, requestedTop=230.4, chromeHeight=180,
                          desiredBodyHeight=600, minimumBodyHeight=240, reserveHeight=30)
        self.assertAlmostEqual(g.property("cardTop"), 230.4)
        self.assertAlmostEqual(g.property("bodyHeight"), 600)

    def test_compact_prompt_grows_without_moving_or_leaving_screen(self):
        height, gap, minimum, reserve = 2304, 10, 240, 30
        g = self.geometry(viewportHeight=height, gap=gap, requestedTop=height * .9, chromeHeight=150,
                          desiredBodyHeight=0, minimumBodyHeight=minimum, reserveHeight=reserve)
        compact_top = g.property("cardTop")
        self.assertEqual(g.property("bodyHeight"), 0)
        # Typing: spacing, footer and the full body join the card.
        g.setProperty("chromeHeight", 150 + reserve)
        g.setProperty("desiredBodyHeight", height * .95)
        self.assertAlmostEqual(g.property("cardTop"), compact_top)
        self.assertGreaterEqual(g.property("bodyHeight"), minimum)
        self.assertLessEqual(g.property("cardTop") + g.property("cardHeight"), height - gap + .01)
        self.assertAlmostEqual(g.property("contentHeight"), g.property("cardHeight"))

    def test_bottom_anchored_matrix_stays_on_screen(self):
        # Pinned to the bottom (Alt+arrows), the card grows upward from its
        # bottom edge and must keep its footer and usable results on screen.
        g = self.component("MenuGeometry.qml")
        for height in [720, 1080, 2304]:
            for chrome in [100, 250, 1000]:
                for bottom in [height * .1, height * .5, height - 10, height * 2]:
                    for body in [0, height * .6, height * .95]:
                        with self.subTest(height=height, chrome=chrome, bottom=bottom, body=body):
                            for key, value in dict(viewportHeight=height, gap=10, requestedTop=-1, requestedBottom=bottom,
                                                   chromeHeight=chrome, desiredBodyHeight=body,
                                                   minimumBodyHeight=150, reserveHeight=30).items():
                                g.setProperty(key, value)
                            self.assertGreaterEqual(g.property("cardTop"), 10)
                            self.assertLessEqual(g.property("cardTop") + g.property("cardHeight"), height - 10 + .01)
                            self.assertGreaterEqual(g.property("bodyHeight"), min(body, 150))
                            self.assertAlmostEqual(g.property("contentHeight"), chrome + g.property("bodyHeight"))

    def test_bottom_anchored_card_grows_up_from_a_fixed_edge(self):
        height, gap, reserve = 1080, 10, 30
        edge = height - gap - height * .12
        g = self.geometry(viewportHeight=height, gap=gap, requestedBottom=edge, chromeHeight=150,
                          desiredBodyHeight=0, minimumBodyHeight=240, reserveHeight=reserve)
        self.assertAlmostEqual(g.property("cardTop") + g.property("cardHeight"), edge)
        g.setProperty("chromeHeight", 150 + reserve)
        g.setProperty("desiredBodyHeight", 400)
        self.assertAlmostEqual(g.property("cardTop") + g.property("cardHeight"), edge)
        self.assertAlmostEqual(g.property("bodyHeight"), 400)

    def test_pinning_to_the_bottom_is_no_binding_loop(self):
        # Alt+Down from a centred or top card pins it to the bottom: cardTop
        # then follows the content height, which must not still follow cardTop
        # from the card's last placement (the shell logged a binding loop).
        from PySide6.QtCore import qInstallMessageHandler
        warnings = []
        previous = qInstallMessageHandler(lambda kind, ctx, msg: warnings.append(msg))
        try:
            for top in [-1, 200]:
                with self.subTest(top=top):
                    g = self.geometry(viewportHeight=900, gap=5, requestedTop=top, chromeHeight=170,
                                      desiredBodyHeight=540, minimumBodyHeight=240, reserveHeight=30)
                    g.property("bodyHeight")
                    g.setProperty("requestedBottom", 787)
                    self.assertAlmostEqual(g.property("cardTop") + g.property("cardHeight"), 787)
        finally:
            qInstallMessageHandler(previous)
        self.assertEqual([w for w in warnings if "Binding loop" in w], [])

    def test_bottom_edge_too_high_is_lowered_to_fit(self):
        g = self.geometry(viewportHeight=1080, gap=10, requestedBottom=100, chromeHeight=180,
                          desiredBodyHeight=600, minimumBodyHeight=240, reserveHeight=30)
        self.assertEqual(g.property("cardTop"), 10)
        self.assertGreaterEqual(g.property("bodyHeight"), 240)

    def test_rows_bottom_edge_matches_the_raised_card_edge(self):
        # The menu budgets its rows against rowsBottomEdge; once the rows want
        # at least minimumBodyHeight it must be the edge the card ends at.
        from PySide6.QtCore import Q_ARG, Q_RETURN_ARG, QMetaObject, Qt
        for bottom in [100, 300, 1000]:
            with self.subTest(bottom=bottom):
                g = self.geometry(viewportHeight=1080, gap=10, requestedBottom=bottom, chromeHeight=180,
                                  desiredBodyHeight=600, minimumBodyHeight=240, reserveHeight=30)
                edge = QMetaObject.invokeMethod(g, "rowsBottomEdge", Qt.DirectConnection,
                                                Q_RETURN_ARG("QVariant"), Q_ARG("QVariant", 180))
                self.assertAlmostEqual(edge, g.property("bottomEdge"))
                self.assertAlmostEqual(edge, g.property("cardTop") + g.property("cardHeight"))

    def test_centre_shift_moves_and_stays_on_screen(self):
        g = self.geometry(viewportHeight=1080, gap=10, requestedTop=-1, chromeHeight=180,
                          desiredBodyHeight=400, minimumBodyHeight=240, reserveHeight=30)
        centred = g.property("cardTop")
        g.setProperty("centerShift", -100)
        self.assertAlmostEqual(g.property("cardTop"), centred - 100)
        g.setProperty("centerShift", 5000)
        self.assertAlmostEqual(g.property("cardTop") + g.property("cardHeight"), 1080 - 10)


if __name__ == "__main__":
    unittest.main()
