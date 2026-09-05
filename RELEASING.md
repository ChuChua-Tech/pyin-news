# Releasing PYIN News

This file records the repeatable release and Omarchy marketplace process for
maintainers.

## Marketplace listing

- Repository: `https://github.com/chuchua-tech/pyin-news`
- Category: `Productivity`
- Tags: `Media`, `Quickshell`, `AI`
- Suggested missing tag: `News`

Maintainer notes:

> PYIN uses theme-native QML plus a standard-library-only Python helper. It has
> no installer, privileged operations, package-manager step, background system
> service, analytics, or account. It contacts configured RSS/Atom and article
> hosts. AI is optional and user-invoked: System AI uses the user's configured
> Codex provider, Local server is restricted to loopback, and No AI remains a
> complete reader. `notify-send` is optional for alerts. User state remains in
> XDG config/state directories and is documented in the README.

## Release checklist

1. Update `manifest.json`, backend `APP_VERSION` and user agent, and `CHANGELOG.md` to the
   same version.
2. Run `python -m py_compile bin/chuchua-news tests/test_release.py`.
3. Run `python -m unittest discover -s tests -v`.
4. Run `node --test tests/test_reading_ui.cjs` and check the changed QML in the
   native app. Plugin validation checks package structure, not rendered behavior.
5. Run `omarchy plugin validate .` on current Omarchy.
6. Run a full refresh from an empty temporary XDG state directory and review
   every source error.
7. Verify App & Updates reports development checkouts as protected, then test a
   stable fast-forward and a validation-failure rollback in an isolated HOME.
8. Incorporate the current `main` into `develop`, commit the release, push
   `develop`, and open a pull request into `main`.
9. Wait for the required Python 3.13 and 3.14 checks on the final pull request
   head, resolve conversations, and merge through the protected branch workflow.
   Do not bypass branch protection or force-push production. Verify `main` CI.
10. Install from the public GitHub URL into a clean Omarchy profile; test first
   launch, update, and removal.
11. Tag the verified `main` merge commit as `v<version>`, push the tag, and create
    the GitHub release with user-facing changes and upgrade information.
12. Verify the published tag, release, and tag CI. Keep `develop` aligned with
    the production merge for subsequent work. The native updater follows `main`.
13. Submit through the official Omarchy plugin form only for an initial listing.

Do not tag a release while the worktree is dirty or CI is failing.
