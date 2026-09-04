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

1. Update `manifest.json`, the backend user agent, and `CHANGELOG.md` to the
   same version.
2. Run `python -m py_compile bin/chuchua-news tests/test_release.py`.
3. Run `python -m unittest discover -s tests -v`.
4. Run `omarchy plugin validate .` on current Omarchy.
5. Run a full refresh from an empty temporary XDG state directory and review
   every source error.
6. Commit, push `main`, and wait for GitHub Actions to pass.
7. Install from the public GitHub URL into a clean Omarchy profile; test first
   launch, update, and removal.
8. Tag the verified commit as `v<version>` and create the GitHub release.
9. Submit the repository through the official Omarchy plugin form.

Do not tag a release while the worktree is dirty or CI is failing.
