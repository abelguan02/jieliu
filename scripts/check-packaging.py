"""Run packaging control flow with fake signing/notary/disk tools; never launch an app."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="jieliu-packaging-check-") as directory:
    root = Path(directory)
    scripts = root / "scripts"
    scripts.mkdir()
    (root / "dist").mkdir()
    for name in ("release.sh", "package-local.sh"):
        shutil.copy2(repo / "scripts" / name, scripts / name)
    (scripts / "build.sh").write_text("#!/bin/bash\nexit 0\n")
    app = root / "fixture.app"
    (app / "Contents" / "MacOS").mkdir(parents=True)
    executable = app / "Contents" / "MacOS" / "Jieliu"
    executable.write_text("#!/bin/bash\nexit 99\n")
    executable.chmod(0o755)
    tools = root / "tools"
    tools.mkdir()
    fake = tools / "fake-tool"
    fake.write_text("#!/usr/bin/env python3\nimport json, os, sys\nfrom pathlib import Path\nwith open(os.environ['JIELIU_PACKAGING_LOG'],'a') as log: log.write(json.dumps([Path(sys.argv[0]).name]+sys.argv[1:])+'\\n')\n")
    fake.chmod(0o755)
    for name in ("hdiutil", "xcrun", "codesign", "spctl", "ditto"):
        (tools / name).symlink_to(fake)
    log = root / "calls.jsonl"
    environment = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"],
                       APP_OUTPUT=str(app), SIGNING_IDENTITY="fake-test-identity",
                       NOTARY_PROFILE="fake-test-profile", JIELIU_PACKAGING_LOG=str(log))
    for version in ("9.8.7", "1.0.3"):
        (app / "Contents" / "Info.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": version}))
        log.write_text("")
        for script in ("release.sh", "package-local.sh"):
            subprocess.run(["bash", str(scripts / script)], env=environment, check=True, capture_output=True)
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        images = [Path(call[-1]).name for call in calls if call[0] == "hdiutil"]
        assert images == [f"Jieliu-{version}.dmg", f"Jieliu-{version}-local.dmg"], images
        submissions = [Path(call[3]).name for call in calls if call[:3] == ["xcrun", "notarytool", "submit"]]
        assert submissions == [f"Jieliu-{version}-notarize.zip", f"Jieliu-{version}.dmg"], submissions
        assert all("1.0.0" not in part for call in calls for part in call)
    (app / "Contents" / "Info.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": "bad/version"}))
    for script in ("release.sh", "package-local.sh"):
        log.write_text("")
        result = subprocess.run(["bash", str(scripts / script)], env=environment, capture_output=True)
        assert result.returncode != 0 and not log.read_text(), "Invalid package version was accepted"
    runner=scripts / "macos-background-check.sh"
    shutil.copy2(repo / "scripts" / runner.name,runner)
    entry=tools / "Jieliu"
    entry.write_text("#!/usr/bin/env python3\nimport json, os, sys\nfrom pathlib import Path\nPath(os.environ['JIELIU_PACKAGING_LOG']).write_text(json.dumps(sys.argv[1:]))\n")
    entry.chmod(0o755)
    subprocess.run(["bash",str(runner),str(entry)],env=environment,check=True,capture_output=True)
    assert json.loads(log.read_text())==["--offscreen-check"], "Background runner used an ordinary entry"
    for arguments in ([str(entry),"unexpected"],["Jieliu"]):
        log.write_text("")
        result=subprocess.run(["bash",str(runner),*arguments],env=environment,capture_output=True)
        assert result.returncode!=0 and not log.read_text(), "Unsafe background invocation was accepted"
print("PASS: local/release DMG, signing and notarization names follow bundle version; invalid versions rejected (all external tools mocked)")
print("PASS: background runner always supplies --offscreen-check and rejects ambiguous paths/arguments (fake executable only)")
