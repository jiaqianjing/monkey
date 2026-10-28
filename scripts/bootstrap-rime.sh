#!/bin/bash
set -euo pipefail
MONKEY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export MONKEY_ROOT

# The official release is universal and has no non-system dylib dependencies.
# Homebrew bottles can require the build host's newer macOS, so do not bundle
# the Homebrew library into releases intended for macOS 13.
python3 -u - <<'PY'
import concurrent.futures
import hashlib
import io
import json
import os
import pathlib
import subprocess
import tarfile
import tempfile
import time

root = pathlib.Path(os.environ['MONKEY_ROOT'])
vendor = root / 'Vendor/Rime'
libdir = vendor / 'lib'
licenses = vendor / 'licenses'
downloads = vendor / 'downloads'
for directory in (libdir, licenses, downloads):
    directory.mkdir(parents=True, exist_ok=True)

url = 'https://github.com/rime/librime/releases/download/1.17.0/rime-33e7814-macOS-universal.tar.bz2'
expected = '11d8dc663c6ec06d5ccb6111ba664a9e7b631b703ac6acd07cffbac664021850'
archive = downloads / 'rime-33e7814-macOS-universal.tar.bz2'

def fetch(url):
    return subprocess.check_output(['curl', '--location', '--fail', '--retry', '3',
                                    '--max-time', '120', '--silent', '--show-error', url])

if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
    print('Downloading official librime 1.17.0 universal binary...')
    data = fetch(url)
    if hashlib.sha256(data).hexdigest() != expected:
        raise SystemExit('librime archive SHA-256 mismatch; refusing to bundle it.')
    archive.write_bytes(data)
with tarfile.open(archive, mode='r:bz2') as package:
    # Extract only this known regular file, never arbitrary archive paths.
    data = package.extractfile('dist/lib/librime.1.17.0.dylib').read()
    (libdir / 'librime.1.dylib').write_bytes(data)
    bindir = vendor / 'bin'
    bindir.mkdir(exist_ok=True)
    deployer = bindir / 'rime_deployer'
    deployer.write_bytes(package.extractfile('dist/bin/rime_deployer').read())
    deployer.chmod(0o755)

# The release links these dependencies statically. Preserve upstream notices
# from the exact source submodule revisions used by librime 33e7814.
sources = [
    ('librime', 'rime/librime', '33e7814', 'LICENSE'),
    ('glog', 'google/glog', '7b134a5c82c0c0b5698bb6bf7a835b230c5638e4', 'COPYING'),
    ('leveldb', 'google/leveldb', '99b3c03b3284f5886f9ef9a4ef703d57373e61be', 'LICENSE'),
    ('marisa-trie', 's-yata/marisa-trie', '3e87d53b78e15f2f43783d5e376561a8c9722051', 'COPYING.md'),
    ('opencc', 'BYVoid/OpenCC', '556ed22496d650bd0b13b6c163be9814637970ae', 'LICENSE'),
    ('yaml-cpp', 'jbeder/yaml-cpp', '2f86d13775d119edbb69af52e5f566fd65c6953b', 'LICENSE'),
    ('boost', 'boostorg/boost', 'boost-1.89.0', 'LICENSE_1_0.txt'),
    ('opencc-marisa', 'BYVoid/OpenCC', '556ed22496d650bd0b13b6c163be9814637970ae', 'deps/marisa-0.2.6/COPYING.md'),
    ('darts-clone', 'rime/librime', '33e7814', 'include/COPYING.darts-clone'),
    ('utf8cpp', 'rime/librime', '33e7814', 'include/utf8.h'),
    ('rapidjson', 'Tencent/rapidjson', 'v1.1.0', 'license.txt'),
]

def license_file(item):
    name, repo, revision, path = item
    target = licenses / (name + '.txt')
    notice_url = f'https://raw.githubusercontent.com/{repo}/{revision}/{path}'
    if not target.exists():
        data = fetch(notice_url)
        if name == 'utf8cpp':
            # Preserve the copyright line plus the complete leading BSL
            # statement; do not copy the implementation/header body.
            end = data.find(b'*/')
            if end < 0 or b'Copyright' not in data[:end]:
                raise RuntimeError('Unable to identify the complete utf8cpp license header.')
            data = data[:end + 2] + b'\n'
        target.write_bytes(data)
    return {'component': name, 'source': f'https://github.com/{repo}/tree/{revision}',
            'notice_source': notice_url, 'notice': target.name,
            'sha256': hashlib.sha256(target.read_bytes()).hexdigest()}

with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
    source_manifest = list(pool.map(license_file, sources))
(licenses / 'SOURCES.json').write_text(json.dumps(source_manifest, indent=2) + '\n')
subprocess.run(['codesign', '--force', '--sign', '-', str(libdir / 'librime.1.dylib')], check=True)
build = subprocess.check_output(['xcrun', 'vtool', '-show-build', str(libdir / 'librime.1.dylib')], text=True)
dependencies = subprocess.check_output(['otool', '-L', str(libdir / 'librime.1.dylib')], text=True)
manifest = (f'Official librime 1.17.0 / source revision 33e7814\n{url}\n'
            f'Archive SHA-256: {expected}\n\n{build}\n{dependencies}')
(vendor / 'BUILD-MANIFEST.txt').write_text(manifest)
print('Ready: Vendor/Rime/lib/librime.1.dylib (arm64 + x86_64).')

# Compile the large, shared dictionary at build time. The bundle includes this
# generated directory, so first use only creates the small per-user config.
shared = root / 'Resources/Rime'
staging = shared / 'build'
staging.mkdir(exist_ok=True)
environment = os.environ.copy()
environment['DYLD_LIBRARY_PATH'] = str(libdir)
started = time.monotonic()
print('Preparing the bundled pinyin dictionary...')
with tempfile.TemporaryDirectory(prefix='monkey-rime-build-') as temporary:
    log = vendor / 'dictionary-build.log'
    with log.open('w') as output:
        result = subprocess.run([str(deployer), '--build', temporary, str(shared), str(staging)],
                                env=environment, stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        print(log.read_text()[-12000:])
        raise SystemExit('Dictionary deployment failed; see Vendor/Rime/dictionary-build.log.')
required = ['monkey_pinyin.table.bin', 'monkey_pinyin.prism.bin', 'monkey_pinyin.schema.yaml', 'default.yaml']
if not all((staging / item).exists() for item in required):
    raise SystemExit('Dictionary deployment did not create all required files.')
print(f'Bundled dictionary ready in {time.monotonic() - started:.1f}s: {staging}')
PY
