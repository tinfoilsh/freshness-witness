import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class FreshnessPredicateTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        self.script = Path(__file__).resolve().parent / "check-and-attest.sh"
        self.digest = "a" * 64
        self.commit = "b" * 40
        git = self.work / "git"
        git.write_text(
            '#!/bin/bash\n'
            'if [ "$1" = ls-remote ]; then\n'
            f'  printf "%s\\t%s\\n" "{self.commit}" "refs/tags/v1.2.3"\n'
            'else\n'
            f'  exec "{shutil.which("git")}" "$@"\n'
            'fi\n'
        )
        git.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.work) + os.pathsep + os.environ["PATH"], GITHUB_OUTPUT=str(self.work / "outputs"))

    def run_script(self, repo, *artifact):
        return subprocess.run(
            ["bash", str(self.script), repo, "v1.2.3", self.digest, *artifact],
            cwd=self.work, env=self.env, capture_output=True, text=True,
        )

    def test_default_and_igvm_subjects_bind_the_same_exact_release(self):
        for repo, artifact in (
            ("owner/workload", "tinfoil-deployment.json"),
            ("tinfoilsh/platform-endorsements", "platform-endorsements.json"),
            ("tinfoilsh/platform-endorsements", "platform-endorsements-igvm.json"),
        ):
            with self.subTest(artifact=artifact):
                override = (artifact,) if artifact.endswith("-igvm.json") else ()
                result = self.run_script(repo, *override)
                self.assertEqual(result.returncode, 0, result.stderr)
                predicate = json.loads((self.work / "predicate.json").read_text())
                self.assertEqual(predicate["endorses"], {
                    "repo": repo, "tag": "v1.2.3", "commit": self.commit,
                    "subject": {"name": artifact, "digest": "sha256:" + self.digest},
                })
                self.assertIn("subject_name=" + artifact, (self.work / "outputs").read_text())

    def test_rejects_other_repository_or_artifact_overrides(self):
        for repo, artifact in (
            ("owner/workload", "platform-endorsements-igvm.json"),
            ("tinfoilsh/platform-endorsements", "other.json"),
        ):
            with self.subTest(repo=repo, artifact=artifact):
                result = self.run_script(repo, artifact)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.work / "predicate.json").exists())


if __name__ == "__main__":
    unittest.main()
