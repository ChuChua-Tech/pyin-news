# Releasing PYIN News

This file records the repeatable release and Omarchy marketplace process for
maintainers.

## Marketplace listing

- Repository: `https://github.com/chuchua-tech/pyin-news`
- Category: `Productivity`
- Tags: `media`, `quickshell`, `ai`
- Suggested missing tag: `News`

Maintainer notes:

> PYIN uses theme-native QML plus a standard-library-only Python helper. It has
> no installer, privileged operations, package-manager step, background system
> service, analytics, or account. It contacts configured RSS/Atom and article
> hosts, plus feed-supplied image hosts only when article images are enabled.
> Images use a bounded XDG cache. AI is optional and user-invoked: System AI uses the selected
> Codex, Claude Code, Gemini CLI or Grok Build's model settings in a private
> Bubblewrap runtime with tools disabled. Bubblewrap and the chosen agent must
> already be installed; the plugin does not install them. Local server is
> restricted to loopback, and No AI remains a
> complete reader. `notify-send` is optional for alerts. User state remains in
> XDG config/state directories and is documented in the README.

## Release checklist

1. Update `manifest.json`, backend `APP_VERSION` and both backend/image user agents, and `CHANGELOG.md` to the
   same version.
2. Run `python -m py_compile bin/chuchua-news bin/news_images.py bin/news_http.py bin/news_ai.py tests/native_ai_contract.py`.
3. Run `python -m unittest discover -s tests -v`.
4. Run `node --test tests/test_reading_ui.cjs` and check the changed QML in the
   native app. Plugin validation checks package structure, not rendered behavior.
5. Run `omarchy plugin validate .` on current Omarchy.
6. Run a full refresh from an empty temporary XDG state directory and review
   every source error.
7. Verify App shows local version information with no update action. Test an
   Omarchy-managed update and validation-failure rollback in a disposable profile
   with isolated user directories. PYIN must not invoke the updater itself.
8. Incorporate the current `main` into `develop`, commit the release, push
   `develop`, and open a pull request into `main`.
9. Wait for the Python 3.13 and 3.14 checks and the native AI boundary check on the final pull request
   head, resolve conversations, and merge through the protected branch workflow.
   Do not bypass branch protection or force-push production. Verify `main` CI.
10. Install from the public GitHub URL into a clean Omarchy profile; test first
   launch, update, and removal.
11. Tag the verified `main` merge commit as `v<version>`, push the tag, and create
    the GitHub release with user-facing changes and upgrade information.
12. Verify the published tag, release, and tag CI. Keep `develop` aligned with
    the production merge for subsequent work. Omarchy manages plugin updates.
13. For an initial listing, use the official Omarchy plugin form. While an
    existing submission is awaiting approval, edit that same issue with the
    released version and exact production commit to rerun compatibility and
    security baseline checks. Verify both bot results identify that commit;
    passing checks still require maintainer approval.

Do not tag a release while the worktree is dirty or CI is failing.

## Native AI compatibility

Run `python tests/native_ai_contract.py` with the verified agents installed, or
pass selected names such as `python tests/native_ai_contract.py codex`. The test
creates disposable homes and a private network, uses fake model responses and
dummy credentials, and checks empty tool offerings, forced tool calls, private
file reads and configuration startup. It does not contact inference services
or use the tester's accounts. The GitHub native-AI job installs explicit agent
versions and runs the same tests.

When an agent version changes, test it before adding it to `VERIFIED_VERSIONS`
in `bin/news_ai.py`. Investigate new tools or configuration behavior instead of
loosening the restrictions. Authentication and refresh need separate native
checks with an authorized account; fixture success does not establish those.
