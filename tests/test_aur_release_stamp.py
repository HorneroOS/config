"""Regression tests for the package-scoped Config AUR release tag."""

from pathlib import Path
import tempfile
import unittest

from scripts.stamp_aur_package import REPOSITORY, stamp

WORKFLOW = Path(__file__).parents[1] / ".github/workflows/aur-publish.yml"
RELEASE_SHA = "a" * 40


class StampReleaseTests(unittest.TestCase):
    def test_aur_workflow_only_listens_to_the_config_package_namespace(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn('"pkg/hornero-config-v*"', workflow)
        self.assertNotIn('"v*"', workflow)
        self.assertIn("RELEASE_SHA: ${{ github.sha }}", workflow)
        self.assertIn('"${RELEASE_SHA}"', workflow)
        self.assertLess(
            workflow.index("Verify release commit is on main"),
            workflow.index("Stamp pkgver and source commit"),
        )

    def test_stamp_updates_version_and_source_tag(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            pkgbuild = Path(directory) / "PKGBUILD"
            pkgbuild.write_text(
                f"pkgver=0.1.0\nsource=(\"config::{REPOSITORY}\")\n",
                encoding="utf-8",
            )

            stamp(pkgbuild, "pkg/hornero-config-v0.2.0_preview1", RELEASE_SHA)

            result = pkgbuild.read_text(encoding="utf-8")
            self.assertIn("pkgver=0.2.0_preview1", result)
            self.assertIn(
                f"{REPOSITORY}#commit={RELEASE_SHA}", result
            )
            self.assertEqual(result.count(REPOSITORY), 1)

    def test_stamp_rejects_unscoped_or_invalid_tags(self) -> None:
        tags = [
            "v0.2.0",
            "pkg/hornero-config-v0.2.0-preview1",
            "pkg/hornero-shell-v0.2.0",
        ]
        with tempfile.TemporaryDirectory() as directory:
            pkgbuild = Path(directory) / "PKGBUILD"
            pkgbuild.write_text(
                f"pkgver=0.1.0\n{REPOSITORY}\n", encoding="utf-8"
            )
            for tag in tags:
                with self.subTest(tag=tag):
                    with self.assertRaises(ValueError):
                        stamp(pkgbuild, tag, RELEASE_SHA)

    def test_stamp_rejects_invalid_release_sha(self) -> None:
        invalid_shas = ["", "a" * 39, "a" * 41, "g" * 40]
        with tempfile.TemporaryDirectory() as directory:
            pkgbuild = Path(directory) / "PKGBUILD"
            pkgbuild.write_text(
                f"pkgver=0.1.0\nsource=(\"config::{REPOSITORY}\")\n",
                encoding="utf-8",
            )
            for release_sha in invalid_shas:
                with self.subTest(release_sha=release_sha):
                    with self.assertRaises(ValueError):
                        stamp(
                            pkgbuild,
                            "pkg/hornero-config-v0.2.0",
                            release_sha,
                        )


if __name__ == "__main__":
    unittest.main()
