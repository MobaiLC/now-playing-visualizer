# SPDX-FileCopyrightText: 2026 MobaiLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""The release and -git PKGBUILDs must agree on every shared field."""

import subprocess
import unittest
from pathlib import Path

AUR = Path(__file__).resolve().parent.parent / "packaging" / "aur"
SHARED = ["pkgdesc", "url", "license", "depends", "optdepends", "makedepends", "arch"]


def fields(pkgbuild):
    # bash itself parses the arrays; declare -p prints each one canonically
    out = subprocess.run(["bash", "-c", 'source "$0" && declare -p "$@"', str(pkgbuild), *SHARED],
                         capture_output=True, text=True, check=True).stdout
    return out.splitlines()


class PkgbuildsInSync(unittest.TestCase):
    def test_shared_fields_match(self):
        release = fields(AUR / "now-playing-visualizer" / "PKGBUILD")
        git = fields(AUR / "now-playing-visualizer-git" / "PKGBUILD")
        self.assertEqual(len(release), len(SHARED))
        self.assertEqual(release, git)


if __name__ == "__main__":
    unittest.main()
