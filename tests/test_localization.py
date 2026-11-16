import contextlib
import io
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from pypdf import PdfWriter

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

import optimizer as opt  # noqa: E402


class LocalizationTests(unittest.TestCase):
    def setUp(self):
        self.catalogs = {
            name: json.loads((ROOT / "locales" / f"{name}.json").read_text())
            for name in opt.SUPPORTED
        }

    def tearDown(self):
        opt.set_language("en")

    def test_all_languages_have_the_same_keys_and_placeholders(self):
        english = self.catalogs["en"]
        for language, catalog in self.catalogs.items():
            self.assertEqual(set(english), set(catalog), language)
            for key, value in catalog.items():
                self.assertTrue(value.strip(), (language, key))
                self.assertEqual(
                    set(re.findall(r"\{[a-z_]+\}", english[key])),
                    set(re.findall(r"\{[a-z_]+\}", value)),
                    (language, key),
                )

    def test_source_keys_are_present(self):
        used = set()
        for path in (ROOT / "src").glob("*"):
            if path.suffix in (".swift", ".py"):
                used.update(
                    re.findall(
                        r"[\'\"]((?:app|drop|file|target|unit|mode|repair|action|status|detail|footer|preview|metrics|checks|menu|language|about|error|progress)\.[a-z_.]+)[\'\"]",
                        path.read_text(),
                    )
                )
        self.assertFalse(used - set(self.catalogs["en"]), used - set(self.catalogs["en"]))

    def test_worker_protocol_and_messages_in_every_language(self):
        for language, catalog in self.catalogs.items():
            opt.set_language(language)
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                opt.emit(
                    "progress", message_key="progress.pages", values={"current": 2, "total": 7}
                )
            event = json.loads(output.getvalue())
            self.assertEqual(event["message_key"], "progress.pages")
            self.assertEqual(event["message"], catalog["progress.pages"].format(current=2, total=7))

    def test_encrypted_pdf_error_is_localized(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "locked.pdf"
            writer = PdfWriter()
            writer.add_blank_page(width=100, height=100)
            writer.encrypt("test-password")
            writer.write(source)
            for language, catalog in self.catalogs.items():
                destination = Path(directory) / f"{language}.pdf"
                process = subprocess.run(
                    [
                        sys.executable,
                        "-B",
                        str(ROOT / "src" / "optimizer.py"),
                        "--input",
                        str(source),
                        "--output",
                        str(destination),
                        "--language",
                        language,
                    ],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                event = json.loads(process.stdout.strip().splitlines()[-1])
                self.assertEqual(process.returncode, 1)
                self.assertEqual(event["message"], catalog["error.encrypted"])
                self.assertFalse(destination.exists())


if __name__ == "__main__":
    unittest.main()
