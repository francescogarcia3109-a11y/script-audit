#!/usr/bin/env python3
"""
build_rbxmx.py - pack the scanner into one file Roblox Studio can load.

WHAT A .rbxmx ACTUALLY IS
    An uncompressed XML Roblox model. Studio loads every model file sitting in
    the local Plugins folder at startup and runs any Script inside it with
    plugin permissions. So "install" is: drop one file in one folder.

THE SHAPE STUDIO NEEDS
    Folder "ScriptAudit"
      Script       "Plugin"    <- runs; this is the toolbar + widget
      ModuleScript "Scanner"   <- required as script.Parent.Scanner
      ModuleScript "Lexer"     <- required as script.Parent.Lexer
    Plugin.server.lua says script.Parent.Scanner, so the three MUST be
    siblings under one parent. That is the only reason the Folder is here.

WHY CDATA AND NOT ESCAPING
    Roblox writes source as <ProtectedString><![CDATA[...]]></ProtectedString>.
    CDATA has exactly one thing that can break it: the sequence ]]> inside the
    payload. Lua long brackets end with ]] and a following > is legal Lua, so
    this is a real hazard, not a theoretical one. We refuse to build rather
    than emit a file that silently truncates a script.
"""
import os, sys, xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT  = os.path.join(HERE, 'dist', 'ScriptAudit.rbxmx')

PARTS = [
    ('Script',       'Plugin',  'plugin/Plugin.server.lua'),
    ('ModuleScript', 'Scanner', 'src/Scanner.lua'),
    ('ModuleScript', 'Lexer',   'src/Lexer.lua'),
]

def read(rel):
    p = os.path.join(HERE, rel)
    if not os.path.exists(p):
        sys.exit('MISSING SOURCE: %s' % rel)
    with open(p, encoding='utf-8') as f:
        s = f.read()
    if ']]>' in s:
        sys.exit('REFUSING TO BUILD: %s contains "]]>", which terminates CDATA '
                 'early and would silently truncate the script inside Studio.' % rel)
    # A lone NUL or a control char would also make the XML invalid.
    bad = [c for c in s if ord(c) < 0x20 and c not in '\t\n\r']
    if bad:
        sys.exit('REFUSING TO BUILD: %s contains control characters.' % rel)
    return s

def main():
    lines = []
    lines.append('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
                 'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
                 'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" '
                 'version="4">')
    lines.append('  <Item class="Folder" referent="RBX0">')
    lines.append('    <Properties>')
    lines.append('      <string name="Name">ScriptAudit</string>')
    lines.append('    </Properties>')
    for i, (cls, name, rel) in enumerate(PARTS, start=1):
        src = read(rel)
        lines.append('    <Item class="%s" referent="RBX%d">' % (cls, i))
        lines.append('      <Properties>')
        lines.append('        <string name="Name">%s</string>' % name)
        lines.append('        <ProtectedString name="Source"><![CDATA[')
        lines.append(src)
        lines.append(']]></ProtectedString>')
        lines.append('      </Properties>')
        lines.append('    </Item>')
    lines.append('  </Item>')
    lines.append('</roblox>')
    xml = '\n'.join(lines) + '\n'

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write(xml)

    # --- self-check: parse what we just wrote and compare it back to source.
    # Writing a file is not the same as writing a file Studio can read.
    root = ET.parse(OUT).getroot()
    found = {}
    for item in root.iter('Item'):
        props = item.find('Properties')
        if props is None:
            continue
        nm = props.find("string[@name='Name']")
        sc = props.find("ProtectedString[@name='Source']")
        if nm is not None and sc is not None:
            found[nm.text] = (item.get('class'), sc.text or '')

    ok = True
    for cls, name, rel in PARTS:
        if name not in found:
            print('FAIL  %-8s missing from the built file' % name); ok = False; continue
        gotcls, gotsrc = found[name]
        if gotcls != cls:
            print('FAIL  %-8s class is %s, expected %s' % (name, gotcls, cls)); ok = False
        # CDATA round-trips with the newline we added on each side.
        if gotsrc.strip('\n') != read(rel).strip('\n'):
            print('FAIL  %-8s source does not round-trip' % name); ok = False
        else:
            print('ok    %-8s %-9s %6d chars round-trip clean' % (name, cls, len(read(rel))))

    print('\n%s  (%d bytes)' % (OUT, os.path.getsize(OUT)))
    print('BUILD OK' if ok else 'BUILD FAILED')
    sys.exit(0 if ok else 1)

if __name__ == '__main__':
    main()
