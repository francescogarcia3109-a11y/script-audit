#!/usr/bin/env python3
"""
build_stress_place.py - a place big enough to make the plugin work for a living.

WHY THIS IS A SEPARATE TOOL
    The seven-script place tests whether the ANSWER is right. It cannot test
    any of the code that only runs when a place is large: the yield inside the
    scan loop, the progress counter, cancel, the MAX_ROWS cap, the batched
    Output print. Every one of those was written to stop Studio freezing, and
    not one of them had ever executed.

    A place with a few thousand scripts is ordinary on Roblox. This builds one.

SHAPE
    Real places are nested and are mostly ordinary code with a few nasty files
    in it. So: scripts live in folders inside services (which exercises
    GetDescendants properly), roughly one in twelve is a backdoor, and the
    sources are the real corpus rather than filler.

USAGE
    python tools/build_stress_place.py            2000 scripts
    python tools/build_stress_place.py 5000       5000 scripts
"""
import os, sys, glob, xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(HERE, 'dist', 'ScriptAuditStressPlace.rbxlx')
SERVICES = ['ServerScriptService', 'ReplicatedStorage', 'StarterGui',
            'ServerStorage', 'Workspace']
PER_FOLDER = 40
BAD_EVERY = 12


def corpus(sub):
    out = []
    for p in sorted(glob.glob(os.path.join(HERE, 'corpus', sub, '*.lua'))):
        with open(p, encoding='utf-8') as f:
            s = f.read()
        if ']]>' in s:
            continue          # would terminate CDATA early; skip rather than corrupt
        out.append((os.path.relpath(p, HERE).replace(os.sep, '/'), s))
    return out


def esc(s):
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 2000
    clean = corpus('holdout-clean') + corpus('clean')
    bad = corpus('holdout-malicious')
    if not clean or not bad:
        sys.exit('corpus not found')

    # service -> list of (folder_name, [ (cls, name, rel, src) ])
    tree = {s: [] for s in SERVICES}
    made, folder, nbad = 0, 0, 0
    while made < n:
        kids = []
        for _ in range(min(PER_FOLDER, n - made)):
            if made % BAD_EVERY == BAD_EVERY - 1:
                rel, src = bad[made % len(bad)]
                nbad += 1
            else:
                rel, src = clean[made % len(clean)]
            cls = 'Script' if made % 3 == 0 else 'ModuleScript'
            kids.append((cls, 'S%05d' % made, rel, src))
            made += 1
        tree[SERVICES[folder % len(SERVICES)]].append(('Pack%03d' % folder, kids))
        folder += 1

    ref = [0]
    def nxt():
        ref[0] += 1
        return 'RBX%d' % ref[0]

    out = ['<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
           'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
           'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" '
           'version="4">']
    for svc in SERVICES:
        # Each service appears EXACTLY ONCE at the top level. A place file with
        # two <Item class="Workspace"> is not a place file.
        out.append('  <Item class="%s" referent="%s">' % (svc, nxt()))
        out.append('    <Properties><string name="Name">%s</string></Properties>' % svc)
        for fname, kids in tree[svc]:
            out.append('    <Item class="Folder" referent="%s">' % nxt())
            out.append('      <Properties><string name="Name">%s</string></Properties>' % esc(fname))
            for cls, name, rel, src in kids:
                out.append('      <Item class="%s" referent="%s">' % (cls, nxt()))
                out.append('        <Properties>')
                out.append('          <string name="Name">%s</string>' % esc(name))
                out.append('          <ProtectedString name="Source"><![CDATA[')
                out.append(src)
                out.append(']]></ProtectedString>')
                out.append('        </Properties>')
                out.append('      </Item>')
            out.append('    </Item>')
        out.append('  </Item>')
    out.append('</roblox>')

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(out) + '\n')

    # Writing a file is not the same as writing a file Studio can read.
    root = ET.parse(OUT).getroot()
    got = sum(1 for i in root.iter('Item')
              if i.find('Properties') is not None
              and i.find('Properties').find("ProtectedString[@name='Source']") is not None)
    services = [i.get('class') for i in root if i.tag == 'Item']
    assert got == n, 'round-trip lost scripts: %d of %d' % (got, n)
    assert len(services) == len(set(services)), 'a service appears twice: %s' % services

    print('%s  (%.1f MB)' % (OUT, os.path.getsize(OUT) / 1e6))
    print('%d scripts in %d folders across %d services. %d are backdoors.'
          % (n, folder, len(SERVICES), nbad))
    print()
    print('WHAT THIS TEST IS FOR - none of it is about the findings:')
    print('  1. Studio must stay responsive during the scan (the loop yields).')
    print('  2. The progress counter must actually move.')
    print('  3. Clicking the same button again must cancel it.')
    print('  4. The report caps at 150 rows and says so; the rest go to Output')
    print('     in batches of 25, not one print per finding.')
    print('  5. Nothing may freeze, and the scan time must be reported.')


if __name__ == '__main__':
    main()
