#!/bin/bash
# Signed/notarized distribution is deliberately separate from development ZIPs.
# Never trace authentication arguments, even when this script is run with bash -x.
set +x
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 - "$ROOT" "$@" <<'PY'
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

parser = argparse.ArgumentParser(description="Build and verify both Developer ID/notarization rounds. Never installs or publishes.",
    epilog="Required: MONKEY_SIGNING_IDENTITY='Developer ID Application: … (TEAMID)' and either MONKEY_NOTARY_PROFILE, or MONKEY_NOTARY_KEY_PATH + MONKEY_NOTARY_KEY_ID (MONKEY_NOTARY_ISSUER only for a Team API key). Optional: MONKEY_NOTARY_TIMEOUT=20m, MONKEY_CREATE_DMG=1, MONKEY_NOTARIZED_OUTPUT_DIR=dist/notarized.")
parser.add_argument("--skip-build", action="store_true", help="Reuse dist/Monkey.app; all signature checks still apply")
parser.add_argument("--resume", metavar="DIRECTORY", help="Resume the exact preserved workflow, including existing submission IDs")
root = Path(sys.argv[1]).resolve()
args = parser.parse_args(sys.argv[2:])

class Failure(Exception):
    pass

def require(condition, message):
    if not condition:
        raise Failure(message)

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def digest(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()

def atomic_json(path, value):
    path = Path(path)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")
    os.replace(temporary, path)

state = None
work = None

def save():
    state["updatedAt"] = now()
    atomic_json(work / "verification.json", state)

def run(label, command, timeout=180, check=True, env=None):
    # Neither commands nor raw stderr are printed: authentication is confined to
    # explicitly supplied notarytool arguments and private local diagnostics.
    logs = work / "logs"
    logs.mkdir(exist_ok=True)
    output = logs / (label + ".stdout")
    errors = logs / (label + ".stderr")
    try:
        with output.open("wb") as stdout, errors.open("wb") as stderr:
            result = subprocess.run([str(x) for x in command], cwd=root, env=env,
                stdout=stdout, stderr=stderr, timeout=timeout)
    except subprocess.TimeoutExpired:
        if check:
            raise Failure(label + " exceeded its time limit; diagnostics preserved in " + str(logs))
        return 124, output
    if check and result.returncode != 0:
        raise Failure(label + " failed (exit " + str(result.returncode) + "); inspect " + str(errors))
    return result.returncode, output

def read_json(path):
    try:
        return json.loads(Path(path).read_text())
    except (ValueError, OSError):
        return {}

def plist(app):
    with (app / "Contents/Info.plist").open("rb") as stream:
        return plistlib.load(stream)

def signature(path, label, hardened=True):
    run(label + "-signature", ["codesign", "--verify", "--deep", "--strict", "-R", "=" + requirement, path])
    _, output = run(label + "-identity", ["codesign", "-d", "--verbose=4", path])
    details = output.read_text() + (work / "logs" / (label + "-identity.stderr")).read_text()
    require("Authority=" + identity in details, label + " is not signed by the requested Developer ID identity")
    require("TeamIdentifier=" + team in details, label + " has a different or missing TeamIdentifier")
    require(re.search(r"^Timestamp=.+", details, re.M), label + " has no secure signing timestamp")
    require("Signature=adhoc" not in details, label + " is ad-hoc signed")
    if hardened:
        require(re.search(r"^CodeDirectory .*flags=.*\bruntime\b", details, re.M), label + " has no hardened runtime")
    cdhash = re.search(r"^CDHash=(\S+)", details, re.M)
    return {"teamID": team, "identity": identity, "cdhash": cdhash.group(1) if cdhash else None,
            "hardenedRuntime": hardened, "secureTimestamp": True}

def verify_app(app, label):
    require(app.is_dir(), "Missing app: " + str(app))
    metadata = plist(app)
    expected = {"Monkey.app": ("org.monkey.inputmethod.Monkey", "MonkeyInputMethod"),
        "Monkey Installer.app": ("org.monkey.inputmethod.Installer", "MonkeyInstaller")}.get(app.name)
    require(expected and (metadata.get("CFBundleIdentifier"), metadata.get("CFBundleExecutable")) == expected,
        label + " has an unexpected bundle identifier or executable")
    require(metadata.get("CFBundleShortVersionString") == version, label + " has a different release version")
    result = signature(app, label)
    # The outer signature is necessary but does not establish that every nested
    # Mach-O has the same Developer ID identity, runtime and secure timestamp.
    macho = {bytes.fromhex(x) for x in ("feedface", "cefaedfe", "feedfacf", "cffaedfe", "cafebabe", "bebafeca", "cafebabf", "bfbafeca")}
    count = 0
    for image in sorted(app.rglob("*")):
        require(not image.is_symlink() or image.resolve().is_relative_to(app.resolve()), "App symlink points outside its bundle")
        if image.is_file():
            with image.open("rb") as stream:
                magic = stream.read(4)
            if magic in macho:
                count += 1
                signature(image, label + "-image-" + str(count))
                _, architectures = run(label + "-arch-" + str(count), ["lipo", "-archs", image])
                require(arch in architectures.read_text().split(), label + " contains an image missing the release architecture")
    require(count > 0, "App contains no Mach-O executable")
    result["validatedMachOCount"] = count
    return result

def assess(path, label, app=True):
    _, output = run(label + "-gatekeeper-status", ["spctl", "--status"])
    require("assessments enabled" in output.read_text(), "Gatekeeper is not enabled; cannot claim distribution assessment")
    command = ["spctl", "--assess", "--verbose=4", "--type", "execute" if app else "open"]
    if not app:
        command += ["--context", "context:primary-signature"]
    run(label + "-gatekeeper", command + [path])
    if app and shutil.which("syspolicy_check"):
        run(label + "-syspolicy", ["syspolicy_check", "distribution", path])

def notarize(stage, target, app=True):
    entry = state.setdefault("stages", {}).setdefault(stage, {})
    signed = verify_app(target, stage) if app else signature(target, stage, hardened=False)
    require(not entry.get("signature") or entry["signature"] == signed, "Signed " + stage + " differs from this workflow's saved submission")
    entry["signature"] = signed
    folder = work / "notary" / stage
    folder.mkdir(parents=True, exist_ok=True)
    archive = folder / ("submission.zip" if app else "submission.dmg")
    if app and not archive.exists():
        run(stage + "-archive", ["ditto", "-c", "-k", "--keepParent", target, archive])
    elif not app and not archive.exists():
        shutil.copy2(target, archive)
    uploaded_hash = digest(archive)
    require(not entry.get("submissionSHA256") or entry["submissionSHA256"] == uploaded_hash, "Saved notarization upload changed")
    entry["submissionSHA256"] = uploaded_hash
    save()
    submission_id = entry.get("submissionID")
    if not submission_id:
        require(not entry.get("submissionStarted"), "Earlier upload has no recoverable submission ID; inspect preserved JSON/stderr before starting any new workflow")
        entry["submissionStarted"] = now()
        save()
        code, output = run(stage + "-submit", ["xcrun", "notarytool", "submit", archive, *auth,
            "--wait", "--timeout", wait_duration, "--output-format", "json"], timeout=wait_seconds + 600, check=False)
        reply = read_json(output)
        submission_id = reply.get("id")
        # Preserve the raw response even on --wait timeout or a network failure.
        shutil.copy2(output, folder / "submit.json")
        if submission_id:
            require(re.fullmatch(r"[0-9A-Fa-f-]{36}", submission_id), "Invalid submission ID in notarytool response")
            entry["submissionID"] = submission_id
            (folder / "submission-id.txt").write_text(submission_id + "\n")
        entry["submitExitCode"] = code
        entry["status"] = reply.get("status", "Unknown")
        save()
        require(submission_id, "Upload did not return a submission ID; raw response is preserved in " + str(folder))
    else:
        _, output = run(stage + "-info", ["xcrun", "notarytool", "info", submission_id, *auth, "--output-format", "json"])
        reply = read_json(output)
        shutil.copy2(output, folder / "info.json")
        entry["status"] = reply.get("status", "Unknown")
        save()
        if entry["status"] == "In Progress":
            _, output = run(stage + "-wait", ["xcrun", "notarytool", "wait", submission_id, *auth,
                "--timeout", wait_duration, "--output-format", "json"], timeout=wait_seconds + 60, check=False)
            reply = read_json(output)
            shutil.copy2(output, folder / "wait.json")
            entry["status"] = reply.get("status", "Unknown")
            save()
    if entry["status"] != "Accepted":
        run(stage + "-notary-log", ["xcrun", "notarytool", "log", submission_id, *auth, folder / "notary-log.json"], check=False)
        raise Failure(stage + " notarization is " + entry["status"] + "; no distribution was approved. Resume with --resume " + str(work))
    run(stage + "-notary-log", ["xcrun", "notarytool", "log", submission_id, *auth, folder / "notary-log.json"])
    report = read_json(folder / "notary-log.json")
    require(report.get("status") == "Accepted", stage + " notarization log does not confirm acceptance")
    require(str(report.get("jobId", "")).lower() == submission_id.lower(), stage + " notarization log belongs to another submission")
    issues = report.get("issues") or []
    require(not any(x.get("severity") == "error" for x in issues), stage + " notarization log contains an error")
    entry["notaryWarningCount"] = sum(x.get("severity") == "warning" for x in issues)
    run(stage + "-staple", ["xcrun", "stapler", "staple", target])
    run(stage + "-staple-validate", ["xcrun", "stapler", "validate", target])
    assess(target, stage, app=app)
    entry.update({"stapled": True, "stapleValidated": True, "gatekeeperAccepted": True,
        "syspolicyCheck": bool(app and shutil.which("syspolicy_check")), "verifiedAt": now()})
    save()
    print(stage + ": Accepted, stapled and locally assessed")

try:
    require(sys.platform == "darwin", "Notarization release packaging requires macOS")
    require(sys.version_info >= (3, 9), "Python 3.9 or later is required")
    identity = os.environ.get("MONKEY_SIGNING_IDENTITY", "")
    match = re.fullmatch(r"Developer ID Application: .+ \(([A-Z0-9]{10})\)", identity)
    require(match, "Set MONKEY_SIGNING_IDENTITY explicitly to a Developer ID Application identity; Apple Development/ad-hoc are refused")
    team = match.group(1)
    profile = os.environ.get("MONKEY_NOTARY_PROFILE", "")
    key = os.environ.get("MONKEY_NOTARY_KEY_PATH", "")
    key_id = os.environ.get("MONKEY_NOTARY_KEY_ID", "")
    issuer = os.environ.get("MONKEY_NOTARY_ISSUER", "")
    require(not (profile and (key or key_id or issuer)), "Choose one explicit notarization authentication method")
    if profile:
        auth = ["--keychain-profile", profile]
    else:
        require(key and key_id, "Set MONKEY_NOTARY_PROFILE, or MONKEY_NOTARY_KEY_PATH and MONKEY_NOTARY_KEY_ID; no credentials are discovered automatically")
        key_path = Path(key).expanduser().resolve()
        require(key_path.is_file(), "The explicitly supplied notarization key file does not exist")
        auth = ["--key", str(key_path), "--key-id", key_id]
        if issuer:
            auth += ["--issuer", issuer]
    wait_duration = os.environ.get("MONKEY_NOTARY_TIMEOUT", "20m")
    duration = re.fullmatch(r"([1-9][0-9]*)([smh]?)", wait_duration)
    require(duration, "MONKEY_NOTARY_TIMEOUT must be a positive duration such as 20m")
    wait_seconds = int(duration.group(1)) * {"": 1, "s": 1, "m": 60, "h": 3600}[duration.group(2)]
    require(wait_seconds <= 7200, "MONKEY_NOTARY_TIMEOUT must not exceed 2h")
    create_dmg = os.environ.get("MONKEY_CREATE_DMG", "0") == "1"
    for tool in ["codesign", "security", "xcrun", "spctl", "ditto", "lipo", "python3"]:
        require(shutil.which(tool), "Required tool is missing: " + tool)
    found = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"], capture_output=True, text=True, timeout=30)
    require(found.returncode == 0 and ('"' + identity + '"') in found.stdout, "The explicitly requested Developer ID Application private-key identity is unavailable")
    requirement = 'anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "' + team + '"'
    builder = root / "scripts/build-installer.sh"
    require(builder.is_file(), "Missing scripts/build-installer.sh")
    source_files = [builder, root / "Resources/Info.plist"] + sorted((root / "Installer").rglob("*"))
    source_hash = hashlib.sha256()
    for path in source_files:
        if path.is_file():
            source_hash.update(str(path.relative_to(root)).encode() + b"\0" + path.read_bytes())
    installer_source_hash = source_hash.hexdigest()
    if args.resume:
        work = Path(args.resume).expanduser().resolve()
        state = read_json(work / "verification.json")
        require(state.get("schemaVersion") == 1, "Resume directory has no recognized workflow record")
        require(state.get("identity") == identity and state.get("teamID") == team, "Resume identity differs from the recorded workflow")
        require(state.get("installerSourceSHA256") == installer_source_hash, "Installer source changed; do not mix it into an existing notarization workflow")
        require(state.get("createDMG") == create_dmg, "Resume must keep the original MONKEY_CREATE_DMG setting")
        name = state["name"]
        version = state["version"]
        arch = state["architecture"]
        minimum = state["minimumMacOS"]
    else:
        metadata = plist(root / "dist/Monkey.app") if args.skip_build else None
        if metadata is None:
            with (root / "Resources/Info.plist").open("rb") as stream:
                metadata = plistlib.load(stream)
        version = metadata["CFBundleShortVersionString"]
        require(re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,3}", version), "Unsafe or unexpected bundle version")
        arch = subprocess.check_output(["uname", "-m"], text=True).strip()
        name = "Monkey-" + version + "-macos-" + arch
        base = Path(os.environ.get("MONKEY_NOTARIZED_OUTPUT_DIR", str(root / "dist/notarized"))).expanduser().resolve()
        base.mkdir(parents=True, exist_ok=True)
        work = base / name
        require(not work.exists(), "Output already exists; never overwrite a release. Use --resume " + str(work) + " for the exact preserved workflow")
        work.mkdir(mode=0o700)
        state = {"schemaVersion": 1, "status": "running", "createdAt": now(), "name": name,
            "version": version, "architecture": arch, "identity": identity, "teamID": team,
            "installerSourceSHA256": installer_source_hash, "createDMG": create_dmg,
            "localAssessmentOnly": True, "cleanBrowserDownloadTested": False,
            "authenticationMethod": "keychain-profile" if profile else "explicit-api-key"}
        save()
        if not args.skip_build:
            run("build-payload", [root / "scripts/build-app.sh"], timeout=1800)
        payload_dir = work / "payload"
        payload_dir.mkdir()
        run("copy-payload", ["ditto", root / "dist/Monkey.app", payload_dir / "Monkey.app"])
        metadata = plist(payload_dir / "Monkey.app")
        require(metadata["CFBundleShortVersionString"] == version, "Built payload version changed")
        minimum = metadata["LSMinimumSystemVersion"]
        state["minimumMacOS"] = minimum
        save()
    payload = work / "payload/Monkey.app"
    installer = work / "installer/Monkey Installer.app"
    if state.get("status") == "verified":
        require(state.get("artifacts"), "Completed workflow has no recorded artifacts")
        require(all(state.get("stages", {}).get(stage, {}).get("status") == "Accepted" for stage in ("payload", "installer")), "Completed workflow is missing one notarization acceptance")
        for artifact in state.get("artifacts", []):
            require(digest(work / artifact["name"]) == artifact["sha256"], "Completed release artifact changed")
        print("Completed workflow preserved without overwriting: " + str(work))
        sys.exit(0)
    notarize("payload", payload)
    if not installer.exists():
        installer.parent.mkdir(exist_ok=True)
        environment = os.environ.copy()
        environment.update({"MONKEY_PAYLOAD_APP": str(payload), "MONKEY_INSTALLER_OUTPUT": str(installer), "MONKEY_SIGNING_IDENTITY": identity})
        run("build-installer", [builder, "--skip-build"], timeout=1800, env=environment)
    notarize("installer", installer)
    distribution = work / "distribution" / name
    distribution.mkdir(parents=True, exist_ok=True)
    copy = distribution / "Monkey Installer.app"
    if not copy.exists():
        run("copy-installer", ["ditto", installer, copy])
    require(verify_app(copy, "distribution-installer") == state["stages"]["installer"]["signature"], "Distribution installer differs from the notarized installer")
    run("distribution-staple-validate", ["xcrun", "stapler", "validate", copy])
    readme = (
        "Monkey " + version + "\nmacOS " + minimum + "+ / " + arch + "\n\n"
        "安装：双击 Monkey Installer.app，按窗口说明安装到当前用户的输入法目录。\n"
        "安装后从菜单栏选择 Monkey 拼音。首次安装未出现时请注销再登录。\n"
        "升级会保留用户词库、偏好与账号连接。\n"
        "安装器与输入法均经 Developer ID 签名、Apple 公证并附带公证票据。\n"
        "正常首次下载确认由 macOS 决定；签名与公证不代替实际跨系统安装验收。\n\n"
        "Install: open Monkey Installer.app and follow its instructions.\n"
        "Select Monkey Pinyin from the input menu afterward. Log out and back in if it does not appear.\n"
        "Updates retain your dictionaries, preferences and account connection.\n"
        "Both apps are Developer ID signed, Apple notarized and stapled.\n"
        "macOS may still show its normal first-download confirmation.\n\n"
        "安装 / Installation: https://github.com/jiaqianjing/monkey/blob/main/docs/install.md\n"
        "隐私 / Privacy: https://github.com/jiaqianjing/monkey/blob/main/docs/privacy.md\n")
    readme_path = distribution / "README.txt"
    require(not readme_path.exists() or readme_path.read_text() == readme, "Distribution README changed")
    if not readme_path.exists():
        readme_path.write_text(readme, encoding="utf-8")
    for notice in ["LICENSE", "THIRD_PARTY_NOTICES.md"]:
        destination = distribution / notice
        require(not destination.exists() or destination.read_bytes() == (root / notice).read_bytes(), "Distribution license changed")
        if not destination.exists():
            shutil.copy2(root / notice, destination)
    require(not list(distribution.rglob("*.command")), "Command-file entry points are forbidden in the notarized package")
    pending_zip = work / "notary/distribution-verified.zip"
    if not pending_zip.exists():
        run("package-zip", ["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", distribution, pending_zip])
    roundtrip = Path(tempfile.mkdtemp(prefix="roundtrip-", dir=str(work)))
    run("extract-final-zip", ["ditto", "-x", "-k", pending_zip, roundtrip])
    extracted = roundtrip / name / "Monkey Installer.app"
    require(verify_app(extracted, "roundtrip-installer") == state["stages"]["installer"]["signature"], "ZIP installer differs from the notarized installer")
    require((roundtrip / name / "README.txt").read_text() == readme, "ZIP README differs from the reviewed README")
    require(not list(roundtrip.rglob("*.command")), "ZIP contains a command-file entry point")
    run("roundtrip-staple-validate", ["xcrun", "stapler", "validate", extracted])
    assess(extracted, "roundtrip-installer")
    executable = plist(extracted)["CFBundleExecutable"]
    run("roundtrip-payload-verify", [extracted / "Contents/MacOS" / executable, "--verify-payload"])
    embedded_zip = extracted / "Contents/Resources/MonkeyPayload.zip"
    require(digest(embedded_zip) == plist(extracted).get("MonkeyPayloadSHA256"), "Embedded payload ZIP checksum differs from its signed installer metadata")
    embedded_dir = roundtrip / "embedded-payload"
    embedded_dir.mkdir()
    run("roundtrip-extract-payload", ["ditto", "-x", "-k", embedded_zip, embedded_dir])
    embedded = embedded_dir / "Monkey.app"
    require(verify_app(embedded, "roundtrip-payload") == state["stages"]["payload"]["signature"], "Embedded payload differs from the notarized payload")
    run("roundtrip-payload-staple-validate", ["xcrun", "stapler", "validate", embedded])
    assess(embedded, "roundtrip-payload")
    final_zip = work / (name + "-notarized.zip")
    if final_zip.exists():
        require(digest(final_zip) == digest(pending_zip), "Existing completed ZIP changed; never overwrite it")
    else:
        os.link(pending_zip, final_zip)  # Atomic creation, fails if the final name exists.
    artifacts = [final_zip]
    if create_dmg:
        dmg = work / "notary/distribution.dmg"
        if not dmg.exists():
            run("create-dmg", ["hdiutil", "create", "-volname", "Monkey " + version, "-srcfolder", distribution, "-format", "UDZO", dmg], timeout=600)
            run("sign-dmg", ["codesign", "--sign", identity, "--timestamp", dmg])
        notarize("dmg", dmg, app=False)
        final_dmg = work / (name + "-notarized.dmg")
        if final_dmg.exists():
            require(digest(final_dmg) == digest(dmg), "Existing completed DMG changed; never overwrite it")
        else:
            os.link(dmg, final_dmg)
        artifacts.append(final_dmg)
    state["artifacts"] = [{"name": path.name, "size": path.stat().st_size, "sha256": digest(path)} for path in artifacts]
    state["zipRoundTripVerified"] = True
    state["embeddedPayloadVerified"] = True
    state["status"] = "verified"
    state["completedAt"] = now()
    checksum = work / (name + "-notarized.sha256")
    checksum_text = "".join(item["sha256"] + "  " + item["name"] + "\n" for item in state["artifacts"])
    require(not checksum.exists() or checksum.read_text() == checksum_text, "Refusing to overwrite a changed checksum file")
    if not checksum.exists():
        checksum.write_text(checksum_text)
    save()
    print("Verified notarized artifacts (not installed or published): " + str(work))
    print("Verification record: " + str(work / "verification.json"))
except (Failure, OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
    if state is not None and work is not None:
        state["status"] = "incomplete"
        state["failure"] = str(error)
        try:
            save()
        except OSError:
            pass
    print("Notarized release stopped: " + str(error), file=sys.stderr)
    sys.exit(1)
PY
