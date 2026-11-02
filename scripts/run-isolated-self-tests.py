#!/usr/bin/env python3
"""Run the built binary in a disposable bundle that cannot advertise services."""
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import uuid

application = Path(sys.argv[1] if len(sys.argv) > 1 else 'dist/归屿.app').resolve()
arguments = sys.argv[2:] or ['--self-test']
identifier = 'local.guiyu.selftest.' + uuid.uuid4().hex
with tempfile.TemporaryDirectory(prefix='GuiyuSelfTest-') as directory:
    copy = Path(directory) / '归屿测试.app'
    subprocess.run(['ditto', str(application), str(copy)], check=True)
    info_path = copy / 'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    info.pop('NSServices', None)
    info.update(CFBundleIdentifier=identifier, SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False)
    info_path.write_bytes(plistlib.dumps(info))
    subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(copy)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(copy)], check=True)
    print('SELF-TEST ISOLATION: unique bundle identity, no NSServices; original bundle unchanged', flush=True)
    try:
        subprocess.run([str(copy / 'Contents/MacOS/Guiyu'), *arguments], check=True)
    finally:
        tool = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
        subprocess.run([tool, '-u', str(copy)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(['defaults', 'delete', identifier], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
