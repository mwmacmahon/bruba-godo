#!/usr/bin/env python3
"""
Parse YAML files and extract values for shell scripts.

Usage:
    parse-yaml.py <file> <key>           # Get a specific key
    parse-yaml.py <file> --json          # Output as JSON
    parse-yaml.py <file> --frontmatter   # Extract YAML frontmatter from markdown
    parse-yaml.py <file> --to-json <key> # Output key as JSON with camelCase keys

Examples:
    parse-yaml.py config.yaml ssh.host
    parse-yaml.py config.yaml local --json
    parse-yaml.py config.yaml agents.bruba-main.tools_allow
    parse-yaml.py document.md --frontmatter
    parse-yaml.py config.yaml --to-json openclaw.compaction
"""

import sys
import json
import re

# Try to use PyYAML for proper nested structure support
try:
    import yaml
    HAS_PYYAML = True
except ImportError:
    HAS_PYYAML = False


def parse_yaml(content):
    """
    Parse YAML content. Uses PyYAML if available (required for nested structures),
    falls back to simple parser for basic configs.
    """
    if HAS_PYYAML:
        return yaml.safe_load(content) or {}
    else:
        # Fallback to simple parser (limited - doesn't handle deep nesting)
        return parse_yaml_simple(content)


def parse_yaml_simple(content):
    """
    Simple YAML parser for basic key-value and nested structures.
    WARNING: Does not properly handle deeply nested structures.
    Use PyYAML for full support: pip install pyyaml
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
            if isinstance(value, str) and value.startswith('[') and value.endswith(']'):
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
            elif isinstance(value, str) and value.startswith('-'):
                # Inline list indicator
                current_dict[key] = []
                current_key = key
                current_list = current_dict[key]
                list_indent = indent
            elif isinstance(value, list):
                # Already parsed as inline list
                current_dict[key] = value
                current_key = key
                current_list = None
                list_indent = -1
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
        return parse_yaml(match.group(1))
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


# Key mapping from snake_case YAML to camelCase JSON (for openclaw.json)
SNAKE_TO_CAMEL = {
    'context_pruning': 'contextPruning',
    'memory_search': 'memorySearch',
    'reserve_tokens_floor': 'reserveTokensFloor',
    'memory_flush': 'memoryFlush',
    'soft_threshold_tokens': 'softThresholdTokens',
    'system_prompt': 'systemPrompt',
    'workspace_access': 'workspaceAccess',
    'max_concurrent': 'maxConcurrent',
    'archive_after_minutes': 'archiveAfterMinutes',
    'active_hours': 'activeHours',
    'tools_allow': 'allow',  # Nested under .tools
    'tools_deny': 'deny',    # Nested under .tools
    # Voice settings (STT + TTS)
    'max_bytes': 'maxBytes',
    'timeout_seconds': 'timeoutSeconds',
    'timeout_ms': 'timeoutMs',
    'max_text_length': 'maxTextLength',
    'voice_id': 'voiceId',
    'model_id': 'modelId',
    'voice_settings': 'voiceSettings',
    'similarity_boost': 'similarityBoost',
    # Memory search settings
    'model_path': 'modelPath',
    'session_memory': 'sessionMemory',
}


def snake_to_camel(key):
    """Convert snake_case key to camelCase using mapping, fallback to conversion."""
    if key in SNAKE_TO_CAMEL:
        return SNAKE_TO_CAMEL[key]
    # Fallback: convert snake_case to camelCase
    components = key.split('_')
    return components[0] + ''.join(x.title() for x in components[1:])


def transform_keys_to_camel(obj):
    """Recursively transform all keys from snake_case to camelCase."""
    if isinstance(obj, dict):
        return {snake_to_camel(k): transform_keys_to_camel(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [transform_keys_to_camel(item) for item in obj]
    else:
        return obj


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
        data = parse_yaml(content)
        print(json.dumps(data, indent=2))
    elif operation == '--frontmatter':
        data = extract_frontmatter(content)
        print(json.dumps(data, indent=2))
    elif operation == '--to-json':
        # Output as JSON with camelCase keys
        if len(sys.argv) < 4:
            print("Error: --to-json requires a key path", file=sys.stderr)
            sys.exit(1)
        key_path = sys.argv[3]
        data = parse_yaml(content)
        value = get_nested_value(data, key_path)
        if value is None:
            sys.exit(1)
        # Transform keys to camelCase
        transformed = transform_keys_to_camel(value)
        print(json.dumps(transformed, indent=2))
    else:
        # Get specific key
        data = parse_yaml(content)
        value = get_nested_value(data, operation)
        if value is None:
            sys.exit(1)
        elif isinstance(value, (dict, list)):
            print(json.dumps(value))
        else:
            print(value)


if __name__ == '__main__':
    main()
