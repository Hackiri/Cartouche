"""Checks that a link opened in Cartouche never links this iPhone to a
Cartouche Cloud account by itself (decision 144, amending 136).

cartouche://cloud/link?code=… is a link anyone can make, from any web page,
message or QR code: linked at once, it would tie the player's iPhone to the
account of whoever made the code, whose games then show in the library and
install from that account. So the link fills in the code and opens the page
of Cartouche Cloud, and the page asks the player before it links:

- CartoucheCloudLink.opened keeps the code for the page and opens it, and
  links nothing;
- CartoucheCloudPage asks, in an alert, with the code it was given, and
  links only from the alert's Link; Cancel forgets the code;
- the question says when a link would take the place of the account the
  iPhone is linked to.

Run from the repository root: python3 -m unittest discover -s app/tests -v
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "launcher" / "Sources"
LINK = SOURCES / "CartoucheCloudLink.swift"
PAGE = SOURCES / "CartoucheCloudPage.swift"
TEXT = SOURCES / "CartoucheTextCloud.swift"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def body(source: str, signature: str) -> str:
    """The body of the function that starts with SIGNATURE, by its braces."""
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 0
    for index in range(opening, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[opening + 1:index]
    raise AssertionError(f"no end to {signature}")


class CloudLinkTest(unittest.TestCase):
    def test_a_link_opened_in_cartouche_links_nothing_by_itself(self):
        opened = body(read(LINK), "static func opened(_ url: URL) -> Bool")
        self.assertNotIn(".link(code:", opened)
        self.assertIn("pendingCode = code", opened)
        self.assertIn("opensPage = true", opened)

    def test_the_page_asks_before_it_links_the_code_of_a_link(self):
        page = read(PAGE)
        # The code of a link opens the question, as the page appears or
        # while it shows.
        self.assertGreaterEqual(page.count("askingPending = true"), 2)
        alert = page[page.index(".alert(CartoucheText.cloudPendingQuestion"):]
        alert = alert[:alert.index("} message:")]
        self.assertIn("isPresented: $askingPending", alert)
        self.assertIn("linkNow()", alert)
        self.assertIn("link.pendingCode = nil", alert)
        self.assertIn("role: .cancel", alert)

    def test_a_code_refused_is_not_asked_about_again(self):
        # A code the platform refused stays in the field with why; the page
        # does not ask about it again as it shows again, and a new link
        # clears the refusal first, so that it is asked about.
        page = read(PAGE)
        asks = [line for line in page.splitlines() if "if let pending" in line]
        self.assertEqual(len(asks), 2)
        for line in asks:
            self.assertIn("link.busy == nil", line)
            self.assertIn("link.refusal == nil", line)
        opened = body(read(LINK), "static func opened(_ url: URL) -> Bool")
        self.assertLess(opened.index("refusal = nil"), opened.index("pendingCode = code"))

    def test_the_question_says_the_code_and_when_it_replaces_an_account(self):
        text = read(TEXT)
        message = re.search(r"static func cloudPendingMessage\(_ code: String, linked: Bool\) -> String \{(.*?)\n    \}",
                            text, re.S)
        self.assertIsNotNone(message, "CartoucheText.cloudPendingMessage(_:linked:) not found")
        assert message is not None
        self.assertIn('"cloud.pending.message"', message.group(1))
        self.assertIn('"cloud.pending.message.linked"', message.group(1))
        self.assertIn('"cloud.pending.question"', text)
        page = read(PAGE)
        self.assertIn("CartoucheText.cloudPendingMessage(", page)
        self.assertIn("linked: link.isLinked", page)


if __name__ == "__main__":
    unittest.main()
