"""Exercise real packaging scripts with fake external tools; never launch an app."""
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
    for name in ("build.sh", "release.sh", "package-local.sh"):
        shutil.copy2(repo / "scripts" / name, scripts / name)
    resources = root / "apps" / "macos" / "Resources"
    shutil.copytree(repo / "apps" / "macos" / "Resources", resources)
    app = root / "staging" / "fixture.app"
    compiled = root / "compiled"
    compiled.mkdir()
    executable = compiled / "Jieliu"
    executable.write_text("""#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
assert len(sys.argv) == 3 and sys.argv[1] == '--render-icon', 'Unexpected app invocation'
with open(os.environ['JIELIU_PACKAGING_LOG'], 'a') as log:
    log.write(json.dumps(['Jieliu'] + sys.argv[1:]) + '\\n')
Path(sys.argv[2]).write_bytes(b'fake icon')
""")
    executable.chmod(0o755)
    tools = root / "tools"
    tools.mkdir()
    fake = tools / "fake-tool"
    fake.write_text("""#!/usr/bin/env python3
import json, os, shutil, sys
from pathlib import Path
name, args = Path(sys.argv[0]).name, sys.argv[1:]
with open(os.environ['JIELIU_PACKAGING_LOG'], 'a') as log:
    log.write(json.dumps([name] + args) + '\\n')
if name == 'swift' and '--show-bin-path' in args:
    print(os.environ['JIELIU_PACKAGING_COMPILED'])
elif name == 'lipo':
    assert all(Path(value).is_file() for value in args[1:args.index('-output')])
    shutil.copy2(args[1], args[-1])
elif name == 'hdiutil':
    # Match the real tool's requirement: the output parent must already exist.
    Path(args[-1]).write_bytes(b'fake disk image')
elif name == 'ditto':
    if '-c' in args:
        Path(args[-1]).write_bytes(b'fake archive')
    else:
        shutil.copytree(args[-2], args[-1])
""")
    fake.chmod(0o755)
    for name in ("swift", "lipo", "hdiutil", "xcrun", "codesign", "spctl", "ditto"):
        (tools / name).symlink_to(fake)
    log = root / "calls.jsonl"
    environment = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"],
                       APP_OUTPUT=str(app), SIGNING_IDENTITY="fake-test-identity",
                       NOTARY_PROFILE="fake-test-profile", JIELIU_PACKAGING_LOG=str(log),
                       JIELIU_PACKAGING_COMPILED=str(compiled), UNIVERSAL="0")
    failures = []
    for version in ("9.8.7", "1.0.3"):
        (resources / "Info.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": version}))
        for script in ("build.sh", "package-local.sh", "release.sh"):
            # APP_OUTPUT is outside dist. Each script must work on a clean checkout.
            if (root / "dist").exists():
                shutil.rmtree(root / "dist")
            log.write_text("")
            result = subprocess.run(["bash", str(scripts / script)], env=environment,
                                    capture_output=True, text=True)
            if result.returncode != 0:
                failures.append(f"{script} ({version}) failed without dist: {result.stderr.strip()}")
                continue
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            images = [Path(call[-1]).name for call in calls if call[0] == "hdiutil"]
            expected_images = {"build.sh": [], "package-local.sh": [f"Jieliu-{version}-local.dmg"],
                               "release.sh": [f"Jieliu-{version}.dmg"]}[script]
            assert images == expected_images, images
            for image in images:
                assert (root / "dist" / image).is_file(), image
            submissions = [Path(call[3]).name for call in calls if call[:3] == ["xcrun", "notarytool", "submit"]]
            expected_submissions = [f"Jieliu-{version}-notarize.zip", f"Jieliu-{version}.dmg"] if script == "release.sh" else []
            assert submissions == expected_submissions, submissions
            if script == "release.sh":
                architectures = [call[call.index("--arch") + 1] for call in calls
                                 if call[0] == "swift" and "--product" in call]
                assert architectures == ["arm64", "x86_64"], architectures
            if script != "package-local.sh":
                assert (app / "Contents" / "Resources" / "AppIcon.icns").is_file()
                assert plistlib.loads((app / "Contents" / "Info.plist").read_bytes())["CFBundleShortVersionString"] == version
            assert all("1.0.0" not in part for call in calls for part in call)
    assert not failures, "\n".join(failures)
    for plist in (resources / "Info.plist", app / "Contents" / "Info.plist"):
        plist.write_bytes(plistlib.dumps({"CFBundleShortVersionString": "bad/version"}))
    for script in ("release.sh", "package-local.sh"):
        log.write_text("")
        result = subprocess.run(["bash", str(scripts / script)], env=environment, capture_output=True)
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        assert result.returncode != 0, "Invalid package version was accepted"
        assert not any(call[0] in ("hdiutil", "xcrun", "ditto") for call in calls), "Invalid version was packaged or submitted"
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
print("PASS: real native/universal build and local/release scripts work with custom APP_OUTPUT and no dist (external tools mocked)")
print("PASS: DMG and notarization names follow bundle version; invalid versions rejected before packaging/submission")
print("PASS: background runner always supplies --offscreen-check and rejects ambiguous paths/arguments (fake executable only)")
