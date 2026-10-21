# Tagged CurseForge packaging

Status: the push webhook and tagged-only mode are configured. Verified on 2026-10-20: build 365242 produced file 9273194 from tag v0.4.1-package1. The archive contains the expected 26 addon files under GuildLedger/, with client version 1.60.1 and Release type. Project/file moderation remains separate. Do not push a new version tag until a release is authorized.

## One-time setup

1. Review and push `.pkgmeta` and this document to the public repository without creating a tag. Confirm the project is still set to No automatic packaging before pushing setup commits.
2. In the CurseForge Source settings, choose packaging of tagged commits only, not all commits.
3. Create a dedicated CurseForge API token using the account's API Tokens page. Enter the token directly in GitHub's repository webhook configuration, never in source files, issues, documentation or chat.
4. Add a GitHub repository push webhook using the endpoint format in CurseForge's Automatic Packaging documentation, project ID 1756462, and the token. Follow the documented default webhook settings. Check the webhook delivery result.
5. Project and file moderation requirements still apply. Verify the first authorized tagged build in CurseForge; local layout checks cannot establish backend acceptance of the client's Interface 16001 metadata.

## Release process

1. Copy only audited release source into the repository root. Exclude settings, private guild data and backups.
2. Update Core.lua VERSION, both TOC Version fields and CHANGELOG.md to the same release number. Versions stay explicit so local installs also report correctly.
3. Run regression and release checks in the development workspace. Inspect the public diff for private data and bundled library notices.
4. Push the approved source commit, then create and push a new version tag (for example v0.4.1). Do not move or reuse an existing release tag.
5. Check CurseForge packaging output, file version/game compatibility, release type, changelog, and the extracted GuildLedger/GuildLedger.toc layout before announcing availability.

Tags containing alpha or beta select those release types; use a plain version tag for a full release. A GitHub Release page alone does not replace pushing a version tag. This setup builds on CurseForge; it does not upload an asset to GitHub Releases.

## Package contents

Runtime source and TOCs are at the repository root. package-as places them directly in the installable GuildLedger/ directory. Bundled libraries and their notices remain included; no external dependency downloads or no-library build are configured. RELEASE.md is excluded; player documentation and licenses are included. The addon carries its own All Rights Reserved license; third-party libraries keep their existing licenses.

Official documentation:
- https://support.curseforge.com/support/solutions/articles/9000197281
- https://support.curseforge.com/support/solutions/articles/9000197952-preparing-the-packagemeta-file
