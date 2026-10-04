from pathlib import Path
import subprocess
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
S6_ROOT = "docker/s6-rc.d"


class DockerS6MetadataLfTest(unittest.TestCase):
    def test_docker_s6_metadata_files_are_checked_out_with_lf(self):
        tracked = subprocess.run(
            ["git", "ls-files", S6_ROOT],
            cwd=REPO_ROOT,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.splitlines()

        self.assertTrue(tracked)

        attrs = subprocess.run(
            ["git", "check-attr", "text", "eol", "--", *tracked],
            cwd=REPO_ROOT,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.splitlines()

        by_path = {}
        for line in attrs:
            path, attr, value = line.split(": ", 2)
            by_path.setdefault(path, {})[attr] = value

        self.assertEqual(
            by_path,
            {path: {"text": "set", "eol": "lf"} for path in tracked},
        )


if __name__ == "__main__":
    unittest.main()
