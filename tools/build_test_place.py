#!/usr/bin/env python3
"""
build_test_place.py - a place file to test the plugin against, with no network.

WHY THIS EXISTS
    Studio cannot open a cloud place while the account is moderated - every
    Roblox API returns 403. File > Open from File does not touch the API at
    all, so a place that lives on disk is testable regardless.

WHY IT IS A BETTER TEST ANYWAY
    The scripts planted here are taken verbatim from the corpus, so the correct
    answer is known BEFORE the plugin runs. A scan of a real place tells you
    what the plugin said. A scan of this place tells you whether it was right.

    Four of the seven are ordinary code (a Knit bootstrap, a ProfileService
    wrapper, a DataStore save, a HUD). Three are backdoors. Coverage must find
    the sites in all seven; false alarms on the four ordinary ones are a fail.
"""
import os, sys, xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Two places, on purpose. The second is the first with ONE script added, which
# is the only way to test the thing the product is actually for: not "what is
# in this place" but "what is in this place that was not here last time".
TAMPERED = '--tampered' in sys.argv

# --stress N builds a place with N scripts instead of seven. The point is NOT
# the findings - it is every line of the plugin that only runs on a big place:
# the yield inside the scan loop, the progress counter, cancel, the MAX_ROWS
# cap, and the batched Output print. None of that has ever executed.
STRESS = 0
if '--stress' in sys.argv:
    i = sys.argv.index('--stress')
    STRESS = int(sys.argv[i + 1]) if len(sys.argv) > i + 1 else 2000

OUT = os.path.join(HERE, 'dist',
    'ScriptAuditStressPlace.rbxlx' if STRESS else
    'ScriptAuditTestPlaceTampered.rbxlx' if TAMPERED else 'ScriptAuditTestPlace.rbxlx')

# (service, [(class, name, corpus file or None, expectation)])
PLAN = [
    ('Workspace', [
        ('Script', 'DoorHandler', 'corpus/clean/09_datastore.lua', 'clean'),
    ]),
    ('ServerScriptService', [
        ('Script', 'Runtime', 'corpus/holdout-clean/01_knit_packages.lua', 'clean'),
        ('Script', 'VehicleSpawner', 'corpus/holdout-malicious/25_realistic_backdoor.lua', 'BACKDOOR'),
        ('ModuleScript', 'ProfileWrapper', 'corpus/holdout-clean/06_profileservice.lua', 'clean'),
    ]),
    ('ReplicatedStorage', [
        ('ModuleScript', 'Analytics', 'corpus/holdout-malicious/19_gsub_decode.lua', 'BACKDOOR'),
        ('ModuleScript', 'Settings', None, 'clean'),
    ]),
    ('StarterGui', [
        ('LocalScript', 'HudBoot', 'corpus/holdout-malicious/10_getfenv_stringindex.lua', 'BACKDOOR'),
    ]),
]

# The tampered place is identical except for this one extra script, dropped
# into ReplicatedStorage under an innocuous name - the shape of a backdoor
# arriving in a place you already audited.
if TAMPERED:
    for i, (svc, kids) in enumerate(PLAN):
        if svc == 'ReplicatedStorage':
            PLAN[i] = (svc, kids + [
                ('ModuleScript', 'SoundManager',
                 'corpus/holdout-malicious/05_pcall_require.lua', 'BACKDOOR (NEW)'),
            ])

PLAIN_MODULE = """-- Settings.lua - ordinary configuration table, nothing to load.
local Settings = {}

Settings.MaxPlayers = 12
Settings.RoundSeconds = 180
Settings.Debug = false

return Settings
"""

def build_stress_plan(n):
    # Real places are mostly ordinary code with a few nasty files in it, and
    # they are nested, not flat. Both matter: nesting exercises GetDescendants,
    # and the ratio keeps the report shaped like a real one.
    import glob
    clean = sorted(glob.glob(os.path.join(HERE, 'corpus', 'holdout-clean', '*.lua'))) + \
            sorted(glob.glob(os.path.join(HERE, 'corpus', 'clean', '*.lua')))
    bad = sorted(glob.glob(os.path.join(HERE, 'corpus', 'holdout-malicious', '*.lua')))
    clean = [os.path.relpath(p, HERE).replace(os.sep, '/') for p in clean]
    bad = [os.path.relpath(p, HERE).replace(os.sep, '/') for p in bad]
    plan = []
    per_folder = 40
    made = 0
    folder = 0
    while made < n:
        kids = []
        for j in range(min(per_folder, n - made)):
            # roughly 1 in 12 is a backdoor
            if made % 12 == 11:
                src = bad[made % len(bad)]
                truth = 'BACKDOOR'
            else:
                src = clean[made % len(clean)]
                truth = 'clean'
            cls = 'ModuleScript' if made % 3 else 'Script'
            kids.append((cls, 'S%04d' % made, src, truth))
            made += 1
        svc = ['ServerScriptService', 'ReplicatedStorage', 'StarterGui',
               'ServerStorage', 'Workspace'][folder % 5]
        plan.append((svc, kids, 'Pack%03d' % folder))
        folder += 1
    return plan


def read(rel):
    if rel is None:
        return PLAIN_MODULE
    p = os.path.join(HERE, rel)
    if not os.path.exists(p):
        sys.exit('MISSING: %s' % rel)
    with open(p, encoding='utf-8') as f:
        s = f.read()
    if ']]>' in s:
        sys.exit('REFUSING: %s contains "]]>" and would truncate inside CDATA' % rel)
    return s

def main():
    ref = 0
    out = ['<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
           'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
           'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" '
           'version="4">']
    manifest = []
    seen_services = set()
    for entry in PLAN:
        service, kids = entry[0], entry[1]
        folder = entry[2] if len(entry) > 2 else None
        # A service may only appear once at the top level of a place file.
        if service in seen_services and folder is None:
            sys.exit('duplicate service %s' % service)
        seen_services.add(service)
        out.append('  <Item class="%s" referent="RBX%d">' % (service, ref)); ref += 1
        out.append('    <Properties>')
        out.append('      <string name="Name">%s</string>' % service)
        out.append('    </Properties>')
        for cls, name, rel, expect in kids:
            src = read(rel)
            out.append('    <Item class="%s" referent="RBX%d">' % (cls, ref)); ref += 1
            out.append('      <Properties>')
            out.append('        <string name="Name">%s</string>' % name)
            out.append('        <ProtectedString name="Source"><![CDATA[')
            out.append(src)
            out.append(']]></ProtectedString>')
            out.append('      </Properties>')
            out.append('    </Item>')
            manifest.append((service, cls, name, expect, rel or '(written here)'))
        out.append('  </Item>')
    out.append('</roblox>')

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(out) + '\n')

    # Writing a file is not the same as writing a file Studio can read.
    root = ET.parse(OUT).getroot()
    scripts = 0
    for item in root.iter('Item'):
        p = item.find('Properties')
        if p is not None and p.find("ProtectedString[@name='Source']") is not None:
            scripts += 1
    assert scripts == len(manifest), 'round-trip lost scripts: %d vs %d' % (scripts, len(manifest))

    print('%s  (%d bytes)\n' % (OUT, os.path.getsize(OUT)))
    print('EXPECTED ANSWER - what a correct scan must say')
    print('%-22s %-13s %-15s %s' % ('service', 'class', 'name', 'truth'))
    for svc, cls, name, expect, rel in manifest:
        print('%-22s %-13s %-15s %s' % (svc, cls, name, expect))
    # startswith, not ==, because the tampered place labels one 'BACKDOOR (NEW)'.
    # An expected-answer generator that states the wrong expected answer is the
    # exact failure this whole file exists to prevent.
    bad = sum(1 for m in manifest if m[3].startswith('BACKDOOR'))
    print('\n%d scripts: %d ordinary, %d backdoors.' % (len(manifest), len(manifest) - bad, bad))
    if TAMPERED:
        print('\nThis is the TAMPERED place. Scan the clean one first, save it as')
        print('the baseline, then open this one. A correct diff says exactly:')
        print('    1 new, 0 changed, 0 gone   ->   ReplicatedStorage.SoundManager')
    print('PASS  = every script contributes to the site count, and NONE of the')
    print('        %d ordinary ones reaches high or critical.' % (len(manifest) - bad))
    print('BONUS = how many of the %d backdoors get ranked high/critical unaided.' % bad)

if __name__ == '__main__':
    main()
