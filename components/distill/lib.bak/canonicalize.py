"""
Convert JSONL messages to canonical markdown format.
"""

from typing import List


def messages_to_markdown(messages: List[dict], config: dict) -> str:
    """
    Convert a list of messages to markdown format.

    Args:
        messages: List of message dicts from JSONL
        config: Distill configuration

    Returns:
        Markdown string
    """
    processing_config = config.get('processing', {})
    include_tools = processing_config.get('include_tool_outputs', False)
    tool_max_chars = processing_config.get('tool_output_max_chars', 500)
    skip_system = processing_config.get('skip_system', True)

    lines = []

    for msg in messages:
        role = msg.get('role', 'unknown')
        content = msg.get('content', '')

        # Skip system messages if configured
        if skip_system and role == 'system':
            continue

        # Handle different message types
        if role == 'human':
            lines.append(f"**Human:**\n{content}\n")

        elif role == 'assistant':
            lines.append(f"**Assistant:**\n{content}\n")

        elif role == 'tool_use':
            tool_name = msg.get('name', 'unknown')
            tool_input = msg.get('input', {})
            lines.append(f"*[Tool: {tool_name}]*\n")
            if include_tools:
                # Truncate long inputs
                input_str = str(tool_input)
                if len(input_str) > tool_max_chars:
                    input_str = input_str[:tool_max_chars] + "..."
                lines.append(f"```\n{input_str}\n```\n")

        elif role == 'tool_result':
            if include_tools:
                result = str(content)
                if len(result) > tool_max_chars:
                    result = result[:tool_max_chars] + "..."
                lines.append(f"*[Tool Result]*\n```\n{result}\n```\n")

        else:
            # Unknown role - include with label
            lines.append(f"*[{role}]*\n{content}\n")

    return "\n".join(lines)
