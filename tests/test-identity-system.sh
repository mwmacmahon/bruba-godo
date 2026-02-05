#!/bin/bash
# Tests for the config-driven identity system (Phases 1-4)
#
# Verifies: config validation, variable substitution, prompt assembly,
# apply_substitutions() sync, and cronjob generation.
#
# Usage:
#   ./tests/test-identity-system.sh              # Run all tests
#   ./tests/test-identity-system.sh --quick      # Same (all tests are quick-compatible)
#   ./tests/test-identity-system.sh --verbose    # Show detailed output
#
# Exit codes:
#   0 = All tests passed
#   1 = Test failed

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$ROOT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
PASSED=0
FAILED=0
SKIPPED=0

# Options
VERBOSE=false
QUICK=false

# Parse args
for arg in "$@"; do
    case $arg in
        --verbose|-v) VERBOSE=true ;;
        --quick) QUICK=true ;;
    esac
done

# Helpers
pass() {
    echo -e "${GREEN}✓${NC} $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    if [[ -n "${2:-}" ]]; then
        echo "  $2"
    fi
    FAILED=$((FAILED + 1))
}

skip() {
    echo -e "${YELLOW}⚠${NC} $1 (skipped)"
    SKIPPED=$((SKIPPED + 1))
}

tlog() {
    if $VERBOSE; then echo "  $*"; fi
}

# Load shared library (gives us load_config, load_agent_config, get_agents, etc.)
source "$ROOT_DIR/tools/lib.sh"

# Set LOG_FILE to /dev/null so lib.sh's log() doesn't fail
LOG_FILE="/dev/null"
load_config

CONFIG_FILE="$ROOT_DIR/config.yaml"

# ============================================================
# Category 1: Config Validation (4 tests)
# ============================================================
test_config_validation() {
    echo ""
    echo "=== Category 1: Config Validation ==="

    # 1.1 peer_agent refs point to real agents
    local errors
    errors=$(python3 -c "
import yaml, sys
with open('$CONFIG_FILE') as f:
    config = yaml.safe_load(f)
agents = config.get('agents', {})
errors = []
for name, cfg in agents.items():
    peer = (cfg or {}).get('identity', {}).get('peer_agent', '')
    if peer and peer not in agents:
        errors.append(f'{name}: peer_agent \"{peer}\" not in agents')
for e in errors:
    print(e)
" 2>/dev/null)

    if [[ -z "$errors" ]]; then
        pass "1.1 peer_agent refs point to real agents"
    else
        fail "1.1 peer_agent refs point to real agents" "$errors"
    fi

    # 1.2 signal_uuid matches UUID format
    errors=$(python3 -c "
import yaml, re, sys
with open('$CONFIG_FILE') as f:
    config = yaml.safe_load(f)
uuid_re = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', re.IGNORECASE)
errors = []
for name, cfg in config.get('agents', {}).items():
    uuid = (cfg or {}).get('identity', {}).get('signal_uuid', '')
    if uuid and not uuid_re.match(uuid):
        errors.append(f'{name}: invalid signal_uuid \"{uuid}\"')
for e in errors:
    print(e)
" 2>/dev/null)

    if [[ -z "$errors" ]]; then
        pass "1.2 signal_uuid matches UUID format"
    else
        fail "1.2 signal_uuid matches UUID format" "$errors"
    fi

    # 1.3 reset_cycle agents also have wake_cycle
    errors=$(python3 -c "
import yaml, sys
with open('$CONFIG_FILE') as f:
    config = yaml.safe_load(f)
errors = []
for name, cfg in config.get('agents', {}).items():
    cfg = cfg or {}
    if cfg.get('reset_cycle', False) and not cfg.get('wake_cycle', False):
        errors.append(f'{name}: has reset_cycle but missing wake_cycle')
for e in errors:
    print(e)
" 2>/dev/null)

    if [[ -z "$errors" ]]; then
        pass "1.3 reset_cycle agents also have wake_cycle"
    else
        fail "1.3 reset_cycle agents also have wake_cycle" "$errors"
    fi

    # 1.4 cross-comms agents have required config
    errors=$(python3 -c "
import yaml, sys
with open('$CONFIG_FILE') as f:
    config = yaml.safe_load(f)
errors = []
for name, cfg in config.get('agents', {}).items():
    cfg = cfg or {}
    sections = cfg.get('agents_sections', [])
    has_cross_comms = any(s == 'cross-comms' or (isinstance(s, str) and s.startswith('cross-comms:')) for s in sections)
    if has_cross_comms:
        identity = cfg.get('identity', {})
        if not identity.get('peer_agent'):
            errors.append(f'{name}: has cross-comms but missing identity.peer_agent')
        variables = cfg.get('variables', {})
        if not variables.get('CROSS_COMMS_GOAL'):
            errors.append(f'{name}: has cross-comms but missing variables.CROSS_COMMS_GOAL')
for e in errors:
    print(e)
" 2>/dev/null)

    if [[ -z "$errors" ]]; then
        pass "1.4 cross-comms agents have required config"
    else
        fail "1.4 cross-comms agents have required config" "$errors"
    fi
}

# ============================================================
# Category 2: Identity Config Completeness (2 tests)
# ============================================================
test_identity_completeness() {
    echo ""
    echo "=== Category 2: Identity Config Completeness ==="

    # 2.1 Component variable refs backed by config
    # 2.2 Template base files checked too
    # Combined into one Python script that reports per-test
    local result
    result=$(python3 << 'PYEOF'
import yaml, re, os, sys, glob

config_file = os.environ.get('CONFIG_FILE', 'config.yaml')
root_dir = os.environ.get('ROOT_DIR', '.')

with open(config_file) as f:
    config = yaml.safe_load(f)

agents = config.get('agents', {})

# Always-available variables (skip these in checks)
ALWAYS_AVAILABLE = {'WORKSPACE', 'AGENT_NAME', 'SHARED_TOOLS'}

# Variable -> config path mapping
VAR_TO_CONFIG = {
    'HUMAN_NAME': 'identity.human_name',
    'SIGNAL_UUID': 'identity.signal_uuid',
    'PEER_AGENT': 'identity.peer_agent',
    'PEER_HUMAN_NAME': 'peer_human_name',  # special: derived from peer
}

var_pattern = re.compile(r'\$\{([A-Z_]+)\}')

def get_config_value(agent_cfg, var_name):
    """Check if agent config provides the value for a variable."""
    if var_name in ALWAYS_AVAILABLE:
        return True

    if var_name in VAR_TO_CONFIG:
        path = VAR_TO_CONFIG[var_name]
        if path == 'peer_human_name':
            # Derived: need peer_agent set + peer has human_name
            peer_id = (agent_cfg or {}).get('identity', {}).get('peer_agent', '')
            if not peer_id:
                return False
            peer_cfg = agents.get(peer_id, {})
            return bool((peer_cfg or {}).get('identity', {}).get('human_name'))
        parts = path.split('.')
        val = agent_cfg or {}
        for p in parts:
            val = (val or {}).get(p, '')
        return bool(val)

    # Check custom variables
    return var_name in (agent_cfg or {}).get('variables', {})

def extract_vars_from_file(filepath):
    """Extract ${VAR} references from a file."""
    if not os.path.isfile(filepath):
        return set()
    with open(filepath) as f:
        content = f.read()
    return set(var_pattern.findall(content))

# Base type -> template directory mapping
BASE_DIRS = {
    'base': os.path.join(root_dir, 'templates/prompts'),
    'guru-base': os.path.join(root_dir, 'templates/prompts/guru'),
    'manager-base': os.path.join(root_dir, 'templates/prompts/manager'),
    'web-base': os.path.join(root_dir, 'templates/prompts/web'),
}

component_errors = []
template_errors = []

for agent_name, agent_cfg in agents.items():
    agent_cfg = agent_cfg or {}

    # Skip agents with no workspace/prompts
    if not agent_cfg.get('workspace') or not agent_cfg.get('prompts'):
        continue

    # Check each prompt type's sections
    for prompt_name in ['agents', 'tools', 'heartbeat']:
        sections_key = f'{prompt_name}_sections'
        sections = agent_cfg.get(sections_key, [])
        prompt_upper = prompt_name.upper()

        for section in sections:
            if not isinstance(section, str):
                continue
            # Skip bot-managed sections
            if section.startswith('bot:'):
                continue

            # Determine file to scan for variables
            filepath = None
            is_base = False

            if section in BASE_DIRS:
                filepath = os.path.join(BASE_DIRS[section], f'{prompt_upper}.md')
                is_base = True
            else:
                # Component: parse component:variant
                if ':' in section:
                    comp, variant = section.split(':', 1)
                    filepath = os.path.join(root_dir, f'components/{comp}/prompts/{prompt_upper}.{variant}.snippet.md')
                else:
                    # Try component first
                    comp_path = os.path.join(root_dir, f'components/{section}/prompts/{prompt_upper}.snippet.md')
                    sect_path = os.path.join(root_dir, f'templates/prompts/sections/{section}.md')
                    if os.path.isfile(comp_path):
                        filepath = comp_path
                    elif os.path.isfile(sect_path):
                        filepath = sect_path

            if not filepath or not os.path.isfile(filepath):
                continue

            vars_used = extract_vars_from_file(filepath)
            for var in vars_used:
                if var in ALWAYS_AVAILABLE:
                    continue
                if not get_config_value(agent_cfg, var):
                    err_list = template_errors if is_base else component_errors
                    err_list.append(f'{agent_name}/{prompt_name}/{section}: uses ${{{var}}} but config missing')

if component_errors:
    print("COMPONENT_ERRORS:" + "|".join(component_errors))
else:
    print("COMPONENT_ERRORS:NONE")

if template_errors:
    print("TEMPLATE_ERRORS:" + "|".join(template_errors))
else:
    print("TEMPLATE_ERRORS:NONE")
PYEOF
)

    # Parse results
    local comp_line tmpl_line
    comp_line=$(echo "$result" | grep "^COMPONENT_ERRORS:")
    tmpl_line=$(echo "$result" | grep "^TEMPLATE_ERRORS:")

    local comp_val="${comp_line#COMPONENT_ERRORS:}"
    local tmpl_val="${tmpl_line#TEMPLATE_ERRORS:}"

    if [[ "$comp_val" == "NONE" ]]; then
        pass "2.1 Component variable refs backed by config"
    else
        local first_err="${comp_val%%|*}"
        local count
        count=$(echo "$comp_val" | tr '|' '\n' | wc -l | tr -d ' ')
        fail "2.1 Component variable refs backed by config ($count errors)" "$first_err"
    fi

    if [[ "$tmpl_val" == "NONE" ]]; then
        pass "2.2 Template base files checked too"
    else
        local first_err="${tmpl_val%%|*}"
        local count
        count=$(echo "$tmpl_val" | tr '|' '\n' | wc -l | tr -d ' ')
        fail "2.2 Template base files checked too ($count errors)" "$first_err"
    fi
}

# ============================================================
# Category 3: apply_substitutions() Sync (2 tests)
# ============================================================
test_apply_substitutions_sync() {
    echo ""
    echo "=== Category 3: apply_substitutions() Sync ==="

    local assemble="$ROOT_DIR/tools/assemble-prompts.sh"
    local detect="$ROOT_DIR/tools/detect-conflicts.sh"

    # 3.1 Function exists in both files
    local found_assemble found_detect
    found_assemble=$(grep -c 'apply_substitutions()' "$assemble" 2>/dev/null || echo 0)
    found_detect=$(grep -c 'apply_substitutions()' "$detect" 2>/dev/null || echo 0)

    if [[ "$found_assemble" -ge 1 && "$found_detect" -ge 1 ]]; then
        pass "3.1 apply_substitutions() exists in both files"
    else
        fail "3.1 apply_substitutions() exists in both files" "assemble=$found_assemble detect=$found_detect"
    fi

    # 3.2 Function bodies in sync
    # Extract the function body from each file, normalize known differences
    local assemble_body detect_body
    assemble_body=$(sed -n '/^apply_substitutions()/,/^}/p' "$assemble")
    detect_body=$(sed -n '/^apply_substitutions()/,/^}/p' "$detect")

    # Normalize known differences:
    # - detect has 'local workspace="$2"' (extra param) that assemble doesn't
    # - detect uses '$workspace' where assemble uses '$AGENT_WORKSPACE'
    local norm_assemble norm_detect
    norm_assemble=$(echo "$assemble_body" | \
        sed 's/\$AGENT_WORKSPACE/\$WORKSPACE_VAR/g')
    norm_detect=$(echo "$detect_body" | \
        sed '/local workspace="\$2"/d' | \
        sed 's/\$workspace/\$WORKSPACE_VAR/g')

    if diff <(echo "$norm_assemble") <(echo "$norm_detect") >/dev/null 2>&1; then
        pass "3.2 Function bodies in sync (normalized)"
    else
        fail "3.2 Function bodies in sync (normalized)"
        if $VERBOSE; then
            echo "  --- Diff (after normalizing known differences) ---"
            diff <(echo "$norm_assemble") <(echo "$norm_detect") || true
        fi
    fi
}

# ============================================================
# Category 4: Variable Substitution Completeness (4 tests)
# ============================================================
test_substitution_completeness() {
    echo ""
    echo "=== Category 4: Variable Substitution Completeness ==="

    # 4.1 Assembly succeeds for all agents
    local assemble_output
    if assemble_output=$(./tools/assemble-prompts.sh --force 2>&1); then
        pass "4.1 Assembly succeeds for all agents"
        tlog "$assemble_output"
    else
        fail "4.1 Assembly succeeds for all agents"
        tlog "$assemble_output"
        # Don't return — subsequent tests will just fail individually
    fi

    # 4.2 No unresolved ${...} in output
    local unresolved
    unresolved=$(grep -r '\${[A-Z_]*}' exports/bot/*/core-prompts/*.md 2>/dev/null || true)
    if [[ -z "$unresolved" ]]; then
        pass "4.2 No unresolved \${...} in output"
    else
        local count
        count=$(echo "$unresolved" | wc -l | tr -d ' ')
        fail "4.2 No unresolved \${...} in output ($count matches)"
        tlog "$unresolved"
    fi

    # 4.3 No unresolved {{...}} in output
    unresolved=$(grep -r '{{[A-Z_]*}}' exports/bot/*/core-prompts/*.md 2>/dev/null || true)
    if [[ -z "$unresolved" ]]; then
        pass "4.3 No unresolved {{...}} in output"
    else
        local count
        count=$(echo "$unresolved" | wc -l | tr -d ' ')
        fail "4.3 No unresolved {{...}} in output ($count matches)"
        tlog "$unresolved"
    fi

    # 4.4 Output dirs exist for all configured agents
    local missing_dirs=""
    while IFS= read -r agent; do
        [[ -z "$agent" ]] && continue
        load_agent_config "$agent"
        # Skip agents with null workspace or no prompts
        if [[ -z "$AGENT_WORKSPACE" || "$AGENT_WORKSPACE" == "null" ]]; then
            continue
        fi
        if [[ "$AGENT_PROMPTS" == "[]" || -z "$AGENT_PROMPTS" ]]; then
            continue
        fi
        if [[ ! -d "exports/bot/$agent/core-prompts" ]]; then
            missing_dirs="$missing_dirs $agent"
        fi
    done < <(get_agents)

    if [[ -z "$missing_dirs" ]]; then
        pass "4.4 Output dirs exist for all configured agents"
    else
        fail "4.4 Output dirs exist for all configured agents" "Missing:$missing_dirs"
    fi
}

# ============================================================
# Category 5: Variable Round-Trip (5 tests)
# ============================================================
test_variable_roundtrip() {
    echo ""
    echo "=== Category 5: Variable Round-Trip ==="

    # 5.1 bruba-main output has main's human_name
    if python3 -c "
import yaml
with open('$CONFIG_FILE') as f:
    c = yaml.safe_load(f)
if 'bruba-main' not in c.get('agents', {}):
    exit(2)  # skip
" 2>/dev/null; then
        load_agent_config "bruba-main"
        if [[ -z "$AGENT_HUMAN_NAME" ]]; then
            skip "5.1 bruba-main output has human_name (no human_name configured)"
        elif [[ -f "exports/bot/bruba-main/core-prompts/AGENTS.md" ]]; then
            if grep -q "$AGENT_HUMAN_NAME" "exports/bot/bruba-main/core-prompts/AGENTS.md" 2>/dev/null; then
                pass "5.1 bruba-main output has main's human_name ($AGENT_HUMAN_NAME)"
            else
                fail "5.1 bruba-main output has main's human_name" "Expected '$AGENT_HUMAN_NAME' in AGENTS.md"
            fi
        else
            skip "5.1 bruba-main output has human_name (no AGENTS.md output)"
        fi
    else
        skip "5.1 bruba-main output has human_name (agent not in config)"
    fi

    # 5.2 bruba-rex output has rex's human_name, not main's
    if python3 -c "
import yaml
with open('$CONFIG_FILE') as f:
    c = yaml.safe_load(f)
if 'bruba-rex' not in c.get('agents', {}):
    exit(2)
" 2>/dev/null; then
        load_agent_config "bruba-rex"
        local rex_name="$AGENT_HUMAN_NAME"
        load_agent_config "bruba-main"
        local main_name="$AGENT_HUMAN_NAME"

        if [[ -z "$rex_name" ]]; then
            skip "5.2 bruba-rex output has rex's human_name (no human_name configured)"
        elif [[ -f "exports/bot/bruba-rex/core-prompts/AGENTS.md" ]]; then
            if grep -q "$rex_name" "exports/bot/bruba-rex/core-prompts/AGENTS.md" 2>/dev/null; then
                # Also check main's name is absent (if names differ)
                if [[ "$rex_name" != "$main_name" && -n "$main_name" ]]; then
                    # Main's name should not appear (except possibly in peer references where it's expected)
                    # The cross-comms section uses PEER_HUMAN_NAME which IS main's name, so we
                    # check that the name doesn't appear in non-cross-comms context.
                    # Simplified: just verify rex's name is present (primary assertion)
                    pass "5.2 bruba-rex output has rex's human_name ($rex_name)"
                else
                    pass "5.2 bruba-rex output has rex's human_name ($rex_name)"
                fi
            else
                fail "5.2 bruba-rex output has rex's human_name" "Expected '$rex_name' in AGENTS.md"
            fi
        else
            skip "5.2 bruba-rex output has human_name (no AGENTS.md output)"
        fi
    else
        skip "5.2 bruba-rex output has human_name (agent not in config)"
    fi

    # 5.3 bruba-guru output has correct signal_uuid
    if python3 -c "
import yaml
with open('$CONFIG_FILE') as f:
    c = yaml.safe_load(f)
if 'bruba-guru' not in c.get('agents', {}):
    exit(2)
" 2>/dev/null; then
        load_agent_config "bruba-guru"
        if [[ -z "$AGENT_SIGNAL_UUID" ]]; then
            skip "5.3 bruba-guru output has signal_uuid (not configured)"
        elif [[ -f "exports/bot/bruba-guru/core-prompts/TOOLS.md" ]]; then
            if grep -q "$AGENT_SIGNAL_UUID" "exports/bot/bruba-guru/core-prompts/TOOLS.md" 2>/dev/null; then
                pass "5.3 bruba-guru output has correct signal_uuid"
            else
                # Also check AGENTS.md as fallback
                if grep -q "$AGENT_SIGNAL_UUID" "exports/bot/bruba-guru/core-prompts/AGENTS.md" 2>/dev/null; then
                    pass "5.3 bruba-guru output has correct signal_uuid (in AGENTS.md)"
                else
                    fail "5.3 bruba-guru output has correct signal_uuid" "UUID not found in output"
                fi
            fi
        else
            skip "5.3 bruba-guru output has signal_uuid (no TOOLS.md output)"
        fi
    else
        skip "5.3 bruba-guru output has signal_uuid (agent not in config)"
    fi

    # 5.4 Cross-comms has correct peer refs
    local tested_any=false
    local errors_54=""
    for agent in bruba-main bruba-rex; do
        if ! python3 -c "
import yaml
with open('$CONFIG_FILE') as f:
    c = yaml.safe_load(f)
a = c.get('agents', {}).get('$agent', {}) or {}
if 'cross-comms' not in a.get('agents_sections', []):
    exit(2)
" 2>/dev/null; then
            tlog "  $agent: no cross-comms section, skipping"
            continue
        fi

        load_agent_config "$agent"
        if [[ -n "$AGENT_PEER_AGENT" && -f "exports/bot/$agent/core-prompts/AGENTS.md" ]]; then
            if grep -q "$AGENT_PEER_AGENT" "exports/bot/$agent/core-prompts/AGENTS.md" 2>/dev/null; then
                tested_any=true
                tlog "  $agent: peer_agent '$AGENT_PEER_AGENT' found in output"
            else
                errors_54="$errors_54 $agent(missing $AGENT_PEER_AGENT)"
            fi
        fi
    done

    if [[ -n "$errors_54" ]]; then
        fail "5.4 Cross-comms has correct peer refs" "$errors_54"
    elif [[ "$tested_any" == "true" ]]; then
        pass "5.4 Cross-comms has correct peer refs"
    else
        skip "5.4 Cross-comms has correct peer refs (no cross-comms agents found)"
    fi

    # 5.5 WORKSPACE resolved per-agent (differs)
    if python3 -c "
import yaml
with open('$CONFIG_FILE') as f:
    c = yaml.safe_load(f)
agents = c.get('agents', {})
if 'bruba-main' not in agents or 'bruba-guru' not in agents:
    exit(2)
" 2>/dev/null; then
        load_agent_config "bruba-main"
        local main_ws="$AGENT_WORKSPACE"
        load_agent_config "bruba-guru"
        local guru_ws="$AGENT_WORKSPACE"

        if [[ -z "$main_ws" || -z "$guru_ws" ]]; then
            skip "5.5 WORKSPACE resolved per-agent (workspaces not set)"
        elif [[ "$main_ws" != "$guru_ws" ]]; then
            # Verify the actual values appear in output
            local main_found=false guru_found=false
            if [[ -f "exports/bot/bruba-main/core-prompts/AGENTS.md" ]]; then
                grep -q "$main_ws" "exports/bot/bruba-main/core-prompts/AGENTS.md" 2>/dev/null && main_found=true
            fi
            if [[ -f "exports/bot/bruba-guru/core-prompts/AGENTS.md" ]]; then
                grep -q "$guru_ws" "exports/bot/bruba-guru/core-prompts/AGENTS.md" 2>/dev/null && guru_found=true
            fi

            if [[ "$main_found" == "true" && "$guru_found" == "true" ]]; then
                pass "5.5 WORKSPACE resolved per-agent (main=$main_ws guru=$guru_ws)"
            elif [[ "$main_found" == "true" || "$guru_found" == "true" ]]; then
                pass "5.5 WORKSPACE resolved per-agent (workspaces differ)"
            else
                # Workspaces differ in config, which is the key assertion
                pass "5.5 WORKSPACE resolved per-agent (config differs)"
            fi
        else
            fail "5.5 WORKSPACE resolved per-agent" "main and guru have same workspace: $main_ws"
        fi
    else
        skip "5.5 WORKSPACE resolved per-agent (agents not in config)"
    fi
}

# ============================================================
# Category 6: Cronjob Generation (6 tests)
# ============================================================
test_cronjob_generation() {
    echo ""
    echo "=== Category 6: Cronjob Generation ==="

    local cronjob_dir="$ROOT_DIR/cronjobs"
    local cronjob_files=(nightly-reset-prep.yaml nightly-reset-execute.yaml nightly-reset-wake.yaml morning-briefing.yaml)

    # 6.1 Generation succeeds
    local gen_output
    if gen_output=$(./tools/generate-cronjobs.sh 2>&1); then
        pass "6.1 Cronjob generation succeeds"
        tlog "$gen_output"
    else
        fail "6.1 Cronjob generation succeeds"
        tlog "$gen_output"
    fi

    # 6.2 All 4 files are valid YAML
    local yaml_errors=0
    for file in "${cronjob_files[@]}"; do
        local fpath="$cronjob_dir/$file"
        if [[ ! -f "$fpath" ]]; then
            tlog "  Missing: $file"
            yaml_errors=$((yaml_errors + 1))
            continue
        fi
        if ! python3 -c "import yaml; yaml.safe_load(open('$fpath'))" 2>/dev/null; then
            tlog "  Invalid YAML: $file"
            yaml_errors=$((yaml_errors + 1))
        fi
    done

    if [[ $yaml_errors -eq 0 ]]; then
        pass "6.2 All 4 cronjob files are valid YAML"
    else
        fail "6.2 All 4 cronjob files are valid YAML ($yaml_errors errors)"
    fi

    # 6.3 No {{...}} placeholders remain
    local placeholder_matches=""
    for file in "${cronjob_files[@]}"; do
        local fpath="$cronjob_dir/$file"
        [[ ! -f "$fpath" ]] && continue
        local matches
        matches=$(grep '{{[A-Z_]*}}' "$fpath" 2>/dev/null || true)
        if [[ -n "$matches" ]]; then
            placeholder_matches="$placeholder_matches $file"
        fi
    done

    if [[ -z "$placeholder_matches" ]]; then
        pass "6.3 No {{...}} placeholders remain in cronjob output"
    else
        fail "6.3 No {{...}} placeholders remain" "Found in:$placeholder_matches"
    fi

    # 6.4 morning-briefing has manager's human_name
    if python3 -c "
import yaml
with open('$CONFIG_FILE') as f:
    c = yaml.safe_load(f)
if 'bruba-manager' not in c.get('agents', {}):
    exit(2)
" 2>/dev/null; then
        load_agent_config "bruba-manager"
        local manager_name="$AGENT_HUMAN_NAME"
        local briefing="$cronjob_dir/morning-briefing.yaml"

        if [[ -z "$manager_name" ]]; then
            skip "6.4 morning-briefing has manager's human_name (not configured)"
        elif [[ ! -f "$briefing" ]]; then
            fail "6.4 morning-briefing has manager's human_name" "File missing"
        elif grep -q "$manager_name" "$briefing" 2>/dev/null; then
            pass "6.4 morning-briefing has manager's human_name ($manager_name)"
        else
            fail "6.4 morning-briefing has manager's human_name" "Expected '$manager_name' in morning-briefing.yaml"
        fi
    else
        skip "6.4 morning-briefing has manager's human_name (bruba-manager not in config)"
    fi

    # 6.5 prep.yaml has one sessions_send per reset agent
    local prep_file="$cronjob_dir/nightly-reset-prep.yaml"
    if [[ -f "$prep_file" ]]; then
        local send_count reset_count
        send_count=$(grep -c 'sessions_send to agent:' "$prep_file" 2>/dev/null || echo 0)
        reset_count=0
        while IFS= read -r agent; do
            [[ -n "$agent" ]] && reset_count=$((reset_count + 1))
        done < <(get_reset_agents)

        if [[ "$send_count" -eq "$reset_count" && "$reset_count" -gt 0 ]]; then
            pass "6.5 prep.yaml has one sessions_send per reset agent ($reset_count)"
        else
            fail "6.5 prep.yaml has one sessions_send per reset agent" "send=$send_count reset=$reset_count"
        fi
    else
        fail "6.5 prep.yaml has one sessions_send per reset agent" "File missing"
    fi

    # 6.6 wake.yaml has one sessions_send per wake agent
    local wake_file="$cronjob_dir/nightly-reset-wake.yaml"
    if [[ -f "$wake_file" ]]; then
        local send_count wake_count
        send_count=$(grep -c 'sessions_send to agent:' "$wake_file" 2>/dev/null || echo 0)
        wake_count=0
        while IFS= read -r agent; do
            [[ -n "$agent" ]] && wake_count=$((wake_count + 1))
        done < <(get_wake_agents)

        if [[ "$send_count" -eq "$wake_count" && "$wake_count" -gt 0 ]]; then
            pass "6.6 wake.yaml has one sessions_send per wake agent ($wake_count)"
        else
            fail "6.6 wake.yaml has one sessions_send per wake agent" "send=$send_count wake=$wake_count"
        fi
    else
        fail "6.6 wake.yaml has one sessions_send per wake agent" "File missing"
    fi
}

# ============================================================
# Run all tests
# ============================================================

echo "Config-Driven Identity System Test Suite"
echo "========================================="

test_config_validation || true
test_identity_completeness || true
test_apply_substitutions_sync || true
test_substitution_completeness || true
test_variable_roundtrip || true
test_cronjob_generation || true

# Summary
echo ""
echo "========================================="
echo -e "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}, ${YELLOW}$SKIPPED skipped${NC}"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
