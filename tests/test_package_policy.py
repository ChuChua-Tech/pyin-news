"""The Git installation tree must not hide agent-control files behind export rules."""

from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
import io
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
loader = SourceFileLoader('pyin_package_policy', str(ROOT / '.github/scripts/check_release.py'))
spec = spec_from_loader(loader.name, loader)
policy = module_from_spec(spec)
loader.exec_module(policy)


class PackagePolicyTests(unittest.TestCase):
    def test_agent_control_paths_and_unreviewed_runtime_files_are_rejected(self):
        for name in ('SKILL.md', 'skills/news/SKILL.md', 'assets/skill.MD', 'AGENTS.md',
                     'AGENTS.override.md', 'CLAUDE.md', 'CLAUDE.local.md', 'GEMINI.md',
                     'GROK.md', '.cursorrules', '.cursor/rules/news.mdc',
                     '.github/copilot-instructions.md', '.agents/skills/news/SKILL.md',
                     '.claude/settings.json', '.codex/config.toml', 'assets/policy.txt',
                     'tests/AGENTS.md', 'instructions.md', 'bin/unreviewed.py',
                     '/README.md', '../README.md', 'tests/../README.md'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                policy.validate_package_file(name)
        for name in ('assets/summary-format.json', 'README.md', 'bin/chuchua-news',
                     'tests/test_summary_prompt.py', 'tests/test_reading_ui.cjs'):
            policy.validate_package_file(name)

    def test_archive_checks_reject_agent_files_and_links(self):
        for name, kind in (('assets/SKILL.md', tarfile.REGTYPE),
                           ('README.md', tarfile.SYMTYPE), ('README.md', tarfile.LNKTYPE),
                           ('.agents', tarfile.DIRTYPE)):
            with self.subTest(name=name, kind=kind):
                data = io.BytesIO()
                with tarfile.open(fileobj=data, mode='w') as archive:
                    entry = tarfile.TarInfo(name)
                    entry.type = kind
                    if kind in (tarfile.SYMTYPE, tarfile.LNKTYPE):
                        entry.linkname = 'SKILL.md'
                    archive.addfile(entry)
                data.seek(0)
                with tarfile.open(fileobj=data) as archive, self.assertRaises(ValueError):
                    policy.validate_archive(archive)

    def test_export_ignore_cannot_conceal_an_installed_instruction_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            def git(*args):
                return subprocess.check_output(['git', '-c', 'core.hooksPath=/dev/null',
                    '-c', 'commit.gpgsign=false', '-c', 'user.name=Fixture',
                    '-c', 'user.email=fixture@example.invalid', *args], cwd=root, stderr=subprocess.DEVNULL)
            git('init', '-q')
            (root / 'README.md').write_text('Fixture')
            git('add', 'README.md'); git('commit', '-qm', 'Clean fixture')
            self.assertEqual(policy.validate_git_tree(root), ['README.md'])
            (root / 'SKILL.md').write_text('Agent-controlled policy')
            (root / '.gitattributes').write_text('SKILL.md export-ignore\n')
            git('add', '.gitattributes', 'SKILL.md'); git('commit', '-qm', 'Hidden instructions')
            with tarfile.open(fileobj=io.BytesIO(git('archive', 'HEAD'))) as archive:
                self.assertNotIn('SKILL.md', archive.getnames())
                policy.validate_archive(archive)
            with self.assertRaisesRegex(ValueError, 'SKILL.md'):
                policy.validate_git_tree(root)
            git('rm', 'SKILL.md'); git('commit', '-qm', 'Remove instructions')
            policy.validate_git_tree(root)
            (root / 'manifest.json').symlink_to('README.md')
            git('add', 'manifest.json'); git('commit', '-qm', 'Linked runtime fixture')
            with self.assertRaisesRegex(ValueError, 'Non-regular'):
                policy.validate_git_tree(root)
