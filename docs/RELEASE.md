# Release signing and notarization keys

The release workflow reads these GitHub Actions repository secrets.

| Secret | Required | Description |
| --- | --- | --- |
| `MACOS_CERTIFICATE` | For signed/notarized builds | Base64-encoded Developer ID Application `.p12` export |
| `MACOS_CERTIFICATE_PASSWORD` | With certificate | Password chosen when exporting the `.p12` |
| `APPLE_ID` | For notarization | Apple Developer account email |
| `APPLE_TEAM_ID` | For notarization | Apple Developer Team ID (10 characters) |
| `APPLE_APP_PASSWORD` | For notarization | App-specific password for `notarytool` |

Without the certificate and Apple values the workflow still builds an ad-hoc signed draft release. Signing and notarization are skipped.

## 1. Developer ID Application certificate

1. Open Xcode > Settings > Accounts.
2. Select the Apple Developer team.
3. Open Manage Certificates.
4. Create a Developer ID Application certificate.
5. Open Keychain Access > My Certificates.
6. Right-click the certificate and export it as a `.p12` file with a strong password.
7. Encode it:

```bash
base64 -i DeveloperIDApplication.p12 | pbcopy
```

8. Add the clipboard value as `MACOS_CERTIFICATE`.
9. Add the export password as `MACOS_CERTIFICATE_PASSWORD`.

The certificate must include its private key. A certificate without a private key cannot sign builds.

## 2. Team ID

Find the Team ID at developer.apple.com > Membership, or in the certificate's Organizational Unit.

Add it as `APPLE_TEAM_ID`.

## 3. App-specific password

1. Open appleid.apple.com.
2. Sign in with the Apple Developer account.
3. Open Sign-In and Security > App-Specific Passwords.
4. Generate a password named `VSLight notarytool`.
5. Add it as `APPLE_APP_PASSWORD`.

Do not use the main Apple ID password.

## 4. Add secrets to GitHub

Repository > Settings > Secrets and variables > Actions > New repository secret.

Add each secret with the exact name above.

Optionally add a repository variable `MACOS_RUNNER` if the hosted `macos-27` image is unavailable. Use `self-hosted` or another valid runner label.

## 5. Verify

Run the release workflow manually with `workflow_dispatch`. It creates a draft release. Check:

- The app is signed with Developer ID.
- `codesign --verify --deep --strict` passes.
- The notarization status is `Accepted`.
- `stapler validate` passes.
- The ZIP SHA256 matches.

Publish the draft release only after testing on another Mac.
