#!/usr/bin/env python3
"""
Claude Research — Send research questions to Claude.ai Projects via Playwright.

Usage:
    claude-research.py --project URL --question "..." [--output PATH] [--timeout 120]

Exit codes:
    0 = success (result written to output file)
    1 = error (general failure)
    2 = auth expired (need to re-login)
"""

import argparse
import os
import re
import sys
from datetime import datetime
from pathlib import Path

# Add sync dir to path for common module
sys.path.insert(0, str(Path(__file__).parent))

from common import (
    RESULTS_DIR,
    AuthExpiredError,
    build_result,
    check_auth,
    extract_response,
    get_profile_dir,
    load_selectors,
    wait_for_response,
)


def slugify(text, max_len=40):
    """Convert text to a filesystem-safe slug."""
    slug = re.sub(r'[^\w\s-]', '', text.lower())
    slug = re.sub(r'[\s_]+', '-', slug).strip('-')
    return slug[:max_len]


def default_output_path(question):
    """Generate default output path based on timestamp and question."""
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    slug = slugify(question)
    return str(RESULTS_DIR / f"{ts}-{slug}.md")


def run_research(project_url, question, output_path, timeout=120, headless=True):
    """Execute a research query against a Claude.ai Project.

    Args:
        project_url: Full URL to the Claude.ai project.
        question: Research question to ask.
        output_path: Where to write the result markdown.
        timeout: Max seconds to wait for response.
        headless: Run browser without visible window.

    Returns:
        str: Path to the output file.

    Raises:
        AuthExpiredError: If auth has expired.
        RuntimeError: If response extraction fails.
    """
    from playwright.sync_api import sync_playwright

    selectors = load_selectors()
    profile_dir = get_profile_dir()

    # Ensure output directory exists
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)

    with sync_playwright() as p:
        # Launch persistent browser context (keeps cookies/auth)
        context = p.chromium.launch_persistent_context(
            profile_dir,
            headless=headless,
            args=[
                "--disable-blink-features=AutomationControlled",
                "--no-first-run",
                "--no-default-browser-check",
            ],
            viewport={"width": 1280, "height": 900},
            user_agent=(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/120.0.0.0 Safari/537.36"
            ),
        )

        try:
            page = context.pages[0] if context.pages else context.new_page()

            # Navigate to project
            print(f"Navigating to project: {project_url}", file=sys.stderr)
            page.goto(project_url, wait_until="networkidle", timeout=30000)
            page.wait_for_timeout(2000)

            # Check authentication
            check_auth(page, selectors)

            # Click "new chat" if available to start fresh
            chat_sel = selectors.get("chat", {})
            new_chat_sel = chat_sel.get("new_chat", "")
            for sel in new_chat_sel.split(","):
                sel = sel.strip()
                if sel:
                    elem = page.query_selector(sel)
                    if elem:
                        elem.click()
                        page.wait_for_timeout(1500)
                        break

            # Prepare question with research prefix and artifact suppression
            topic = question[:60] if len(question) > 60 else question
            full_question = (
                f"[Research: {topic}]\n\n"
                f"{question}\n\n"
                "Please respond in plain markdown without using Artifacts."
            )

            # Type question into chat input
            input_sel = chat_sel.get("input", "")
            input_elem = None
            for sel in input_sel.split(","):
                sel = sel.strip()
                if sel:
                    input_elem = page.query_selector(sel)
                    if input_elem:
                        break

            if not input_elem:
                raise RuntimeError(
                    "Could not find chat input. Selectors may need updating. "
                    "Run: components/claude-sync/setup.sh --inspect"
                )

            # Fill the input
            input_elem.click()
            page.wait_for_timeout(300)
            input_elem.fill(full_question)
            page.wait_for_timeout(300)

            # Submit
            submit_sel = chat_sel.get("submit", "")
            submitted = False
            for sel in submit_sel.split(","):
                sel = sel.strip()
                if sel:
                    btn = page.query_selector(sel)
                    if btn:
                        btn.click()
                        submitted = True
                        break

            if not submitted:
                # Fallback: press Enter
                input_elem.press("Enter")

            print(f"Question submitted, waiting for response (timeout: {timeout}s)...", file=sys.stderr)

            # Wait for response
            completed = wait_for_response(page, selectors, timeout=timeout)
            if not completed:
                print("WARNING: Response may have timed out", file=sys.stderr)

            # Extract response
            response_text = extract_response(page, selectors)
            if not response_text:
                raise RuntimeError(
                    "No response text extracted. Selectors may need updating. "
                    "Run: components/claude-sync/setup.sh --inspect"
                )

            # Get current URL (may have changed to conversation URL)
            current_url = page.url

            # Extract project name from URL
            project_name = project_url.rstrip("/").split("/")[-1]

            # Build and write result
            result = build_result(
                project=project_name,
                question=question,
                response=response_text,
                url=current_url,
            )

            with open(output_path, "w") as f:
                f.write(result)

            print(f"Result written to: {output_path}", file=sys.stderr)
            # Print output path to stdout for script consumption
            print(output_path)
            return output_path

        finally:
            context.close()


def main():
    parser = argparse.ArgumentParser(
        description="Send research questions to Claude.ai Projects"
    )
    parser.add_argument(
        "--project",
        required=True,
        help="Claude.ai project URL",
    )
    parser.add_argument(
        "--question",
        required=True,
        help="Research question to ask",
    )
    parser.add_argument(
        "--output",
        help="Output file path (default: auto-generated in results/)",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=120,
        help="Max seconds to wait for response (default: 120)",
    )
    parser.add_argument(
        "--headless",
        action="store_true",
        default=True,
        help="Run browser headless (default: true)",
    )
    parser.add_argument(
        "--visible",
        action="store_true",
        help="Run browser with visible window (for debugging)",
    )

    args = parser.parse_args()

    output = args.output or default_output_path(args.question)
    headless = not args.visible

    try:
        run_research(
            project_url=args.project,
            question=args.question,
            output_path=output,
            timeout=args.timeout,
            headless=headless,
        )
        sys.exit(0)

    except AuthExpiredError as e:
        print(f"AUTH EXPIRED: {e}", file=sys.stderr)
        sys.exit(2)

    except KeyboardInterrupt:
        print("Interrupted.", file=sys.stderr)
        sys.exit(1)

    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
