#!/usr/bin/env python3
"""Exercise the shipped cursor and geometry components in the real Qt engine."""
import os
from pathlib import Path
import unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QPA_PLATFORMTHEME", "generic")

from PySide6.QtCore import QEvent, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
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


if __name__ == "__main__":
    unittest.main()
