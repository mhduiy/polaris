#!/usr/bin/env python3

# The QML side binds every reading to the applet by name, and a name the applet
# does not have is not an error in QML: the binding is simply undefined and the
# surface quietly shows nothing. Nothing else in the suite would notice, so the
# names are checked against the applet's own declarations here.
#
# Run through ctest, or directly: python3 tests/test_applet_bindings.py

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
HEADER = ROOT / "src" / "polarisapplet.h"
QML_FILES = [
    ROOT / "package" / "main.qml",
    ROOT / "package" / "DetailPanel.qml",
    ROOT / "package" / "ProcessTable.qml",
]

# `root.source.powerSource.length` reaches a member of the *value*, not of the
# applet; only the first hop is a binding.
JS_MEMBERS = {"length", "toFixed", "indexOf", "values", "map", "filter", "slice", "join", "concat"}


def declared_properties():
    text = HEADER.read_text()
    return set(re.findall(r"Q_PROPERTY\(\s*[\w:<>*& ]+?\s+(\w+)\s", text)) | set(
        re.findall(r"Q_INVOKABLE\s+[\w:<>*&]+?\s+(\w+)\s*\(", text)
    )


def bound_names(path):
    text = path.read_text()
    names = set(re.findall(r"\b[Aa]pplet\.(\w+)", text))
    names |= set(re.findall(r"\broot\.source\.(\w+)", text))
    names |= set(re.findall(r"(?<![\w.])source\.(\w+)", text))
    return names - JS_MEMBERS


def monitor_item_properties():
    text = (ROOT / "package" / "MonitorItem.qml").read_text()
    return set(re.findall(r"^\s*property\s+[\w.]+\s+(\w+)", text, re.M))


def assigned_to_monitor_item():
    """What main.qml sets on the dock item, which must exist on the item.

    QML only warns about an assignment to a property that is not there, so a
    renamed reading would simply stop reaching the taskbar.
    """
    text = (ROOT / "package" / "main.qml").read_text()
    start = text.index("MonitorItem {")
    depth = 0
    end = start
    for index in range(start, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                end = index
                break
    block = text[start:end]
    names = set()
    for line in block.splitlines()[1:]:
        match = re.match(r"\s{8,}([a-z]\w*)\s*:", line)
        if not match:
            continue
        name = match.group(1)
        # `id` is QML's own, and `onFoo:` is a handler rather than a property.
        if name == "id" or name.startswith("on"):
            continue
        names.add(name)
    return names


def main():
    declared = declared_properties()
    if not declared:
        print("FAILED: no properties found in", HEADER)
        return 1

    problems = []
    for path in QML_FILES:
        for name in sorted(bound_names(path)):
            if name not in declared:
                problems.append(f"{path.name} binds {name}, which the applet does not declare")

    item_properties = monitor_item_properties()
    for name in sorted(assigned_to_monitor_item()):
        if name not in item_properties:
            problems.append(f"main.qml sets {name} on the dock item, which does not declare it")

    for problem in problems:
        print("FAILED:", problem)

    if problems:
        return 1

    print(f"binding checks passed ({len(declared)} applet properties)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
