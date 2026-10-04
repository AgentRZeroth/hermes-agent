from pathlib import Path
import subprocess
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
DOCKER_RUNTIME_ROOTS = ("docker/s6-rc.d", "docker/cont-init.d")


class DockerRuntimeMetadataLfTest(unittest.TestCase):
    def test_docker_runtime_metadata_files_are_checked_out_with_lf(self):
        tracked = []
        for root in DOCKER_RUNTIME_ROOTS:
            tracked.extend(
                subprocess.run(
                    ["git", "ls-files", root],
                    cwd=REPO_ROOT,
                    check=True,
                    capture_output=True,
                    text=True,
                ).stdout.splitlines()
            )

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
