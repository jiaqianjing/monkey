# Native installer

`scripts/build-installer.sh` builds the standalone AppKit installer without
changing the SwiftPM package, rebuilding the main app, installing anything or
publishing. Its default output is `dist/Monkey Installer.app`.

For a local, ad-hoc signed preview with installation disabled:

```sh
scripts/build-installer.sh --development --skip-build
"dist/Monkey Installer.app/Contents/MacOS/MonkeyInstaller" --verify-payload
"dist/Monkey Installer.app/Contents/MacOS/MonkeyInstaller" --self-test
```

`--verify-payload` only extracts into a disposable temporary directory and
checks the archive hash, code signature, application ID, fixed executable name
and (in production) Developer ID Team ID. `--self-test` simulates installation
inside a newly created temporary directory using fake apps and injected
commands. It never launches the payload, sends app termination notifications or
accesses the actual input-method installation. There is no CLI option to
install, change the destination or bypass production verification.

The real install begins only after clicking Install. It writes only to the
current account's `~/Library/Input Methods/Monkey.app`, uses a same-volume
private staging directory and installer lock, and rejects symlink or unrelated
app destinations. `NSRunningApplication.terminate()` requests a graceful exit
only for processes whose bundle path exactly matches the installed target;
the installer waits up to five seconds before moving any bundle. It never
force-quits a process or broadcasts Monkey's global `--quit` notification.
The previous bundle is kept
until the replacement is verified and its fixed register/enable commands have
run. Hard failures restore it; registration that merely needs a new login
session is reported as installation complete with further setup required.
Personal data and Keychain entries are outside the installation transaction.
If rollback itself is blocked, its backup is retained and the UI gives its path.

Production inputs are supplied through:

```sh
MONKEY_PAYLOAD_APP="/absolute/path/to/stapled/Monkey.app" \
MONKEY_INSTALLER_OUTPUT="/absolute/output/Monkey Installer.app" \
MONKEY_SIGNING_IDENTITY="Developer ID Application: ..." \
scripts/build-installer.sh --skip-build
```

Production mode requires a valid Developer ID Application signature and a
successful `stapler validate` on the payload before embedding it. After signing
the installer, the script checks that it uses the same Team ID. The sealed ZIP
resource is `Contents/Resources/MonkeyPayload.zip` and contains `Monkey.app`.
No compiler, credentials, `stapler`, `spctl` invocation, privileged helper,
`sudo`, quarantine removal or network request is needed on the user's Mac.

Apple's [custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
explicitly requires **two rounds for a custom installer**: notarize and staple
the payload first, then embed it and notarize/staple the installer. If a DMG is
distributed, sign and notarize that final outer container too. For ZIP delivery,
create the final ZIP after stapling the installer, and validate a fresh
extraction of both its signature and the embedded payload's ticket. Keep this
process in the publisher's release pipeline. Signing or notarizing the outer
installer alone does not establish that the installed payload was stapled.

The local build/self-tests do not establish successful Developer ID signing,
Apple acceptance, download-time Gatekeeper behavior, registration in a fresh
login session or physical user acceptance. Those require the completed release
pipeline and a fresh downloaded copy on a test Mac.
