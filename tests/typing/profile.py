"""Counts from a qmlprofiler trace (.qtd) recorded only while typing
(--record off, console.profile() / profileEnd()): how often each binding,
handler and function ran and how many objects were created. Counts, not
times: they do not depend on how busy the machine is."""
import collections
import os
import xml.etree.ElementTree as ET


def counts(path):
    events, ranges = {}, []
    for _, el in ET.iterparse(path, events=("end",)):
        if el.tag == "event":
            events[int(el.get("index"))] = {c.tag: (c.text or "") for c in el}
            el.clear()
        elif el.tag == "range":
            ranges.append((int(el.get("startTime")), int(el.get("eventIndex"))))
            el.clear()
    out = collections.Counter()
    for t, i in ranges:
        e = events[i]
        kind = e.get("type")
        f = os.path.basename(e.get("filename", ""))
        if kind == "Creating":
            out["created"] += 1
        elif kind == "Javascript":
            what = e.get("details") or ""
            out["js:" + f] += 1
            if what.startswith("expression for"):
                out["bind:" + f] += 1
                out["bind:%s:%s" % (f, what[len("expression for "):])] += 1
            elif what:
                out["call:%s:%s" % (f, what)] += 1
        elif kind == "HandlingSignal":
            out["signal:" + f] += 1
    return out
