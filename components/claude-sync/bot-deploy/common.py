"""
Shared utilities for claude-sync browser automation.

Provides selector loading, auth checking, response extraction,
and result formatting for Claude.ai interactions.
"""

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

# Base directory for claude-sync on the bot
SYNC_DIR = Path("/Users/bruba/claude-sync")
PROFILE_DIR = SYNC_DIR / "profile"
RESULTS_DIR = SYNC_DIR / "results"
SELECTORS_FILE = SYNC_DIR / "selectors.json"


class AuthExpiredError(Exception):
    """Raised when claude.ai session auth has expired."""
    pass


def load_selectors(path=None):
    """Load CSS selectors from selectors.json.

    Args:
        path: Override path to selectors.json. Defaults to SELECTORS_FILE.

    Returns:
        dict: Nested selector definitions.

    Raises:
        FileNotFoundError: If selectors.json doesn't exist.
        json.JSONDecodeError: If selectors.json is malformed.
    """
    sel_path = Path(path) if path else SELECTORS_FILE
    with open(sel_path) as f:
        return json.load(f)


def get_profile_dir():
    """Return path to persistent Chromium profile directory."""
    return str(PROFILE_DIR)


def check_auth(page, selectors):
    """Detect whether the current page is authenticated.

    Args:
        page: Playwright page object.
        selectors: Loaded selectors dict.

    Returns:
        bool: True if authenticated, False if login page detected.

    Raises:
        AuthExpiredError: If login page is clearly detected.
    """
    auth = selectors.get("auth", {})

    # Check for logged-in indicators
    logged_in_sel = auth.get("logged_in", "")
    for sel in logged_in_sel.split(","):
        sel = sel.strip()
        if sel and page.query_selector(sel):
            return True

    # Check for login page indicators
    login_sel = auth.get("login_page", "")
    for sel in login_sel.split(","):
        sel = sel.strip()
        if sel and page.query_selector(sel):
            raise AuthExpiredError(
                "Claude.ai auth expired. Run: "
                "components/claude-sync/setup.sh --login"
            )

    return False


def wait_for_response(page, selectors, timeout=120):
    """Wait for Claude's response to complete.

    Watches for the streaming indicator to appear and disappear,
    then waits for the response content to stabilize.

    Args:
        page: Playwright page object.
        selectors: Loaded selectors dict.
        timeout: Maximum wait time in seconds.

    Returns:
        bool: True if response completed, False if timed out.
    """
    resp = selectors.get("response", {})
    timeout_ms = timeout * 1000

    # Wait for streaming to start (message appears)
    message_sel = resp.get("message", "")
    first_sel = message_sel.split(",")[0].strip()
    try:
        page.wait_for_selector(first_sel, timeout=30000, state="attached")
    except Exception:
        # Response may already be complete or selector mismatch
        pass

    # Wait for stop button to appear (streaming started)
    stop_sel = resp.get("stop_button", "")
    first_stop = stop_sel.split(",")[0].strip()
    try:
        page.wait_for_selector(first_stop, timeout=15000, state="attached")
    except Exception:
        # May have already finished or selector mismatch
        pass

    # Wait for stop button to disappear (streaming finished)
    try:
        page.wait_for_selector(first_stop, timeout=timeout_ms, state="detached")
    except Exception:
        return False

    # Brief settle time for DOM to finalize
    page.wait_for_timeout(1000)
    return True


def extract_response(page, selectors):
    """Extract the last assistant response text from the page.

    Args:
        page: Playwright page object.
        selectors: Loaded selectors dict.

    Returns:
        str: Response text content, or empty string if not found.
    """
    resp = selectors.get("response", {})
    message_sel = resp.get("message", "")

    # Try each selector variant
    for sel in message_sel.split(","):
        sel = sel.strip()
        if not sel:
            continue

        elements = page.query_selector_all(sel)
        if elements:
            # Get the last assistant message
            last = elements[-1]
            return last.inner_text()

    return ""


def build_result(project, question, response, url=None):
    """Build markdown result with YAML frontmatter.

    Args:
        project: Project name/identifier.
        question: Original research question.
        response: Claude's response text.
        url: Optional conversation URL.

    Returns:
        str: Formatted markdown string.
    """
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    lines = [
        "---",
        f"source: claude-research",
        f"project: \"{project}\"",
        f"timestamp: \"{now}\"",
    ]
    if url:
        lines.append(f"url: \"{url}\"")
    lines.extend([
        "---",
        "",
        f"# Research: {question}",
        "",
        response,
        "",
    ])

    return "\n".join(lines)
