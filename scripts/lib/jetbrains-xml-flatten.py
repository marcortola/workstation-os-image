#!/usr/bin/env python3
"""Flatten a JetBrains XML settings file into sorted canonical key lines.

Emitting one deterministic line per element (path + sorted attributes + text)
lets two files be compared structurally with plain `diff`, so cosmetic
differences (attribute order, whitespace, self-closing style) do not register
as divergence while genuine key/value changes do.
"""
import sys
import xml.etree.ElementTree as ET

# Attributes preferred as the element's discriminator so sibling entries
# (actions, options, schemes) align when sorted.
DISCRIMINATORS = ("name", "id", "key", "keymap", "value", "first-keystroke")


def segment(element):
    for attr in DISCRIMINATORS:
        if attr in element.attrib:
            return "%s[%s=%s]" % (element.tag, attr, element.attrib[attr])
    return element.tag


def walk(element, prefix, out):
    path = prefix + "/" + segment(element)
    attrs = " ".join(
        "@%s=%s" % (key, value) for key, value in sorted(element.attrib.items())
    )
    text = (element.text or "").strip()
    line = path
    if attrs:
        line += " " + attrs
    if text:
        line += " = " + text
    out.append(line)
    for child in element:
        walk(child, path, out)


def main():
    if len(sys.argv) != 2:
        sys.stderr.write("usage: jetbrains-xml-flatten.py FILE\n")
        return 2
    try:
        root = ET.parse(sys.argv[1]).getroot()
    except Exception as error:  # noqa: BLE001 - report any parse failure
        sys.stderr.write("parse error: %s\n" % error)
        return 1
    out = []
    walk(root, "", out)
    out.sort()
    sys.stdout.write("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
