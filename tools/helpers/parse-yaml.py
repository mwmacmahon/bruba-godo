#!/usr/bin/env python3
"""
Parse YAML files and extract values for shell scripts.

Usage:
    parse-yaml.py <file> <key>           # Get a specific key
    parse-yaml.py <file> --json          # Output as JSON
    parse-yaml.py <file> --frontmatter   # Extract YAML frontmatter from markdown

Examples:
    parse-yaml.py config.yaml ssh.host
    parse-yaml.py config.yaml local --json
    parse-yaml.py document.md --frontmatter
"""

import sys
import json
import re


def parse_yaml_simple(content):
    """
    Simple YAML parser for basic key-value and nested structures.
    Avoids PyYAML dependency.
    """
    result = {}
    stack = [(result, -1)]  # (dict, indent_level)
    current_key = None
    current_list = None
    list_indent = -1

    for line in content.split('\n'):
        # Skip empty lines (but not lines that are just whitespace for structure)
        if not line.strip():
            continue

        # Skip comment-only lines
        stripped = line.lstrip()
        if stripped.startswith('#'):
            continue

        # Calculate indent
        indent = len(line) - len(stripped)

        # Strip inline comments from stripped (but preserve the stripped content)
        if '#' in stripped and not stripped.startswith('#'):
            # Split on # but be careful about # in quotes
            comment_idx = stripped.find('#')
            # Simple approach: just strip from #
            stripped = stripped[:comment_idx].rstrip()

        # Pop stack to correct level
        while len(stack) > 1 and stack[-1][1] >= indent:
            stack.pop()

        current_dict = stack[-1][0]

        # Handle list items
        if stripped.startswith('- '):
            value = stripped[2:].strip()
            # Track list context
            if current_list is not None and indent >= list_indent:
                current_list.append(value)
            elif current_key and isinstance(current_dict.get(current_key), list):
                current_dict[current_key].append(value)
                current_list = current_dict[current_key]
                list_indent = indent
            continue

        # Handle key-value pairs
        if ':' in stripped:
            parts = stripped.split(':', 1)
            key = parts[0].strip()
            value = parts[1].strip() if len(parts) > 1 else ''

            # Remove quotes from values
            if value.startswith('"') and value.endswith('"'):
                value = value[1:-1]
            elif value.startswith("'") and value.endswith("'"):
                value = value[1:-1]

            # Handle inline lists [a, b, c]
            if value.startswith('[') and value.endswith(']'):
                items = value[1:-1].split(',')
                value = [item.strip().strip('"\'') for item in items if item.strip()]

            if value == '':
                # Check if next non-empty line is a list item at higher indent
                # For now, assume list if key is typical list name
                current_dict[key] = []
                current_key = key
                current_list = current_dict[key]
                list_indent = indent
                stack.append((current_dict, indent))
            elif value.startswith('-'):
                # Inline list indicator
                current_dict[key] = []
                current_key = key
                current_list = current_dict[key]
                list_indent = indent
            else:
                current_dict[key] = value
                current_key = key
                current_list = None
                list_indent = -1

    return result


def extract_frontmatter(content):
    """Extract YAML frontmatter from markdown file."""
    match = re.match(r'^---\s*\n(.*?)\n---\s*\n', content, re.DOTALL)
    if match:
        return parse_yaml_simple(match.group(1))
    return {}


def get_nested_value(data, key_path):
    """Get a nested value using dot notation: 'ssh.host' -> data['ssh']['host']"""
    keys = key_path.split('.')
    current = data
    for key in keys:
        if isinstance(current, dict) and key in current:
            current = current[key]
        else:
            return None
    return current


def main():
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    filepath = sys.argv[1]
    operation = sys.argv[2]

    try:
        with open(filepath, 'r') as f:
            content = f.read()
    except FileNotFoundError:
        print(f"Error: File not found: {filepath}", file=sys.stderr)
        sys.exit(1)

    if operation == '--json':
        data = parse_yaml_simple(content)
        print(json.dumps(data, indent=2))
    elif operation == '--frontmatter':
        data = extract_frontmatter(content)
        print(json.dumps(data, indent=2))
    else:
        # Get specific key
        data = parse_yaml_simple(content)
        value = get_nested_value(data, operation)
        if value is None:
            sys.exit(1)
        elif isinstance(value, (dict, list)):
            print(json.dumps(value))
        else:
            print(value)


if __name__ == '__main__':
    main()
