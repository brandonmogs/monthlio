#!/usr/bin/env python3
"""Merge keys from Swift-emitted .stringsdata files into a String Catalog.

Usage: sync-string-catalog.py <DerivedData> <catalog.xcstrings> <project> [--prune]

Xcode's IDE syncs catalogs during builds; xcodebuild only emits the
.stringsdata sidecars. This adds any key missing from the catalog as a
source-language entry (an empty object, which is how Xcode stores a key
whose English value is the key itself) and reports what changed.
"""
import glob, json, sys, os
derived, catalog, target = sys.argv[1], sys.argv[2], sys.argv[3]
prune = '--prune' in sys.argv[4:]
pattern = os.path.join(derived, '**', f'{target}.build', '**', '*.stringsdata')
files = glob.glob(pattern, recursive=True)
keys = {}
for f in files:
    try:
        data = json.load(open(f))
    except Exception as e:
        print('skip', f, e); continue
    for table, entries in data.get('tables', {}).items():
        if table != 'Localizable':
            continue
        for e in entries:
            k = e.get('key')
            if not k:
                continue
            keys.setdefault(k, e.get('comment'))
cat = json.load(open(catalog))
strings = cat.setdefault('strings', {})
added = []
for k, comment in sorted(keys.items()):
    if k not in strings:
        strings[k] = ({'comment': comment} if comment else {})
        added.append(k)
stale = [k for k in strings if k not in keys]
if prune:
    for k in stale:
        del strings[k]
cat['strings'] = dict(sorted(strings.items()))
json.dump(cat, open(catalog, 'w'), indent=2, ensure_ascii=False)
open(catalog, 'a').write('\n')
print(f'{len(files)} stringsdata files, {len(keys)} keys, added {len(added)}, catalog now {len(strings)}')
for k in added:
    print('  +', k)
if stale:
    print('removed from the catalog (not in this build):' if prune else 'not seen in this build (kept; pass --prune to remove):')
    for k in stale:
        print('  -' if prune else '  ?', k)
