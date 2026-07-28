import os
import stat
import subprocess
import tempfile
import unittest
from unittest import mock

import app


class CookieSelectionTests(unittest.TestCase):
    def test_domain_matching_does_not_use_substrings(self):
        self.assertTrue(app.is_youtube_url("https://music.youtube.com/watch?v=abc"))
        self.assertTrue(app.is_youtube_url("https://youtu.be/abc"))
        self.assertFalse(app.is_youtube_url("https://example.com/?next=youtube.com"))

    def test_only_site_specific_cookie_file_is_selected(self):
        with tempfile.TemporaryDirectory() as directory:
            youtube = os.path.join(directory, "youtube.txt")
            instagram = os.path.join(directory, "instagram.txt")
            open(youtube, "w").close()
            open(instagram, "w").close()

            with mock.patch.object(app, "COOKIES_FILE", youtube), mock.patch.object(
                    app, "INSTAGRAM_COOKIES_FILE", instagram):
                self.assertEqual(youtube, app.get_cookies_file("https://youtube.com/watch?v=x"))
                self.assertEqual(instagram, app.get_cookies_file("https://instagram.com/reel/x"))
                self.assertIsNone(app.get_cookies_file("https://example.com/video"))

    def test_cookie_copy_is_private_and_missing_file_means_no_cookies(self):
        self.assertIsNone(app.make_cookies_copy("missing-cookies.txt"))
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(
                app, "DOWNLOAD_DIR", directory):
            source = os.path.join(directory, "source.txt")
            with open(source, "w", encoding="ascii") as handle:
                handle.write("cookie")
            copied = app.make_cookies_copy(source)
            self.assertTrue(os.path.isfile(copied))
            if os.name == "posix":
                self.assertEqual(stat.S_IMODE(os.stat(copied).st_mode), 0o600)


class DownloadTests(unittest.TestCase):
    def setUp(self):
        app.jobs.clear()

    def test_youtube_retries_with_cookies_and_accepts_combined_format(self):
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(
                app, "DOWNLOAD_DIR", directory), mock.patch.object(
                app, "COOKIES_FILE", os.path.join(directory, "cookies.txt")), mock.patch.object(
                app, "cleanup_file"):
            with open(app.COOKIES_FILE, "w", encoding="ascii") as handle:
                handle.write("cookie")

            job_id = "job"
            app.jobs[job_id] = {"status": "processing"}
            calls = []

            def fake_run(command, **kwargs):
                calls.append(command)
                if "--get-title" in command:
                    return subprocess.CompletedProcess(command, 0, "Test title\n", "")
                if len([call for call in calls if "--get-title" not in call]) == 1:
                    return subprocess.CompletedProcess(command, 1, "", "no formats")
                with open(os.path.join(directory, "job.mp3"), "wb") as handle:
                    handle.write(b"audio")
                return subprocess.CompletedProcess(command, 0, "", "")

            with mock.patch.object(app.subprocess, "run", side_effect=fake_run):
                app.do_download(job_id, "https://www.youtube.com/watch?v=abc", "mp3")

            download_calls = [call for call in calls if "--get-title" not in call]
            self.assertEqual("done", app.jobs[job_id]["status"])
            self.assertNotIn("--cookies", download_calls[0])
            self.assertIn("--cookies", download_calls[1])
            self.assertEqual("bestaudio/best", download_calls[0][download_calls[0].index("-f") + 1])


if __name__ == "__main__":
    unittest.main()
