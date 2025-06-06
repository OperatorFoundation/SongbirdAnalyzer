#!/bin/bash

# =============================================================================
# SONGBIRD TEST RUNNER
# =============================================================================

set -euo pipefail

# Test configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly TEST_RESULTS_DIR="$SCRIPT_DIR/results"
readonly COVERAGE_DIR="$SCRIPT_DIR/coverage"

# Test execution options
RUN_UNIT_TESTS=true
RUN_INTEGRATION_TESTS=true
RUN_BASH_TESTS=true
RUN_PYTHON_TESTS=true
GENERATE_COVERAGE=true
VERBOSE_OUTPUT=false
FAIL_FAST=false

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --unit-only)
                RUN_INTEGRATION_TESTS=false
                shift
                ;;
            --integration-only)
                RUN_UNIT_TESTS=false
                shift
                ;;
            --bash-only)
                RUN_PYTHON_TESTS=false
                shift
                ;;
            --python-only)
                RUN_BASH_TESTS=false
                shift
                ;;
            --no-coverage)
                GENERATE_COVERAGE=false
                shift
                ;;
            --verbose|-v)
                VERBOSE_OUTPUT=true
                shift
                ;;
            --fail-fast)
                FAIL_FAST=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Show usage information
show_usage() {
    cat << EOF
SONGBIRD TEST RUNNER

USAGE:
    $0 [options]

OPTIONS:
    --unit-only      Run only unit tests
    --integration-only  Run only integration tests
    --bash-only      Run only Bash script tests
    --python-only    Run only Python tests
    --no-coverage    Skip coverage report generation
    --verbose, -v    Enable verbose output
    --fail-fast      Stop on first test failure
    --help, -h       Show this help message

EXAMPLES:
    $0                      # Run all tests
    $0 --unit-only -v       # Run unit tests with verbose output
    $0 --python-only        # Run only Python tests
    $0 --no-coverage        # Run tests without coverage
EOF
}

# Setup test environment
setup_test_environment() {
    log_info "Setting up test environment..."

    # Create directories
    mkdir -p "$TEST_RESULTS_DIR"
    mkdir -p "$COVERAGE_DIR"

    # Check prerequisites
    local missing_tools=()

    if [[ "$RUN_BASH_TESTS" == "true" ]] && ! command -v bats &>/dev/null; then
        missing_tools+=("bats (Bash Automated Testing System)")
    fi

    if [[ "$RUN_PYTHON_TESTS" == "true" ]] && ! command -v python3 &>/dev/null; then
        missing_tools+=("python3")
    fi

    if [[ "$GENERATE_COVERAGE" == "true" && "$RUN_PYTHON_TESTS" == "true" ]]; then
        if ! python3 -c "import coverage" &>/dev/null; then
            missing_tools+=("python3-coverage")
        fi
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools:"
        for tool in "${missing_tools[@]}"; do
            log_error "  - $tool"
        done
        exit 1
    fi

    log_success "Test environment setup completed"
}

# Run Bash unit tests
run_bash_unit_tests() {
    if [[ "$RUN_BASH_TESTS" != "true" ]]; then
        return 0
    fi

    log_info "Running Bash unit tests..."

    local test_files=()
    while IFS= read -r -d '' file; do
        test_files+=("$file")
    done < <(find "$SCRIPT_DIR/unit/bash" -name "*.bats" -print0 2>/dev/null)

    if [[ ${#test_files[@]} -eq 0 ]]; then
        log_warning "No Bash test files found"
        return 0
    fi

    local failed_tests=0
    local total_tests=${#test_files[@]}

    for test_file in "${test_files[@]}"; do
        local test_name=$(basename "$test_file" .bats)
        local result_file="$TEST_RESULTS_DIR/bash_${test_name}.tap"

        log_info "  Running: $test_name"

        # Simplified: Don't pass verbose flag to bats, just run normally
        if bats "$test_file" > "$result_file" 2>&1; then
            log_success "    ✅ $test_name passed"
        else
            log_error "    ❌ $test_name failed"
            ((failed_tests++))

            if [[ "$VERBOSE_OUTPUT" == "true" ]]; then
                cat "$result_file"
            fi

            if [[ "$FAIL_FAST" == "true" ]]; then
                log_error "Stopping due to --fail-fast option"
                return 1
            fi
        fi
    done

    if [[ $failed_tests -eq 0 ]]; then
        log_success "All Bash unit tests passed ($total_tests/$total_tests)"
    else
        log_error "Bash unit tests failed: $failed_tests/$total_tests"
        return 1
    fi
}

# Run Python unit tests with proper working directory isolation
run_python_unit_tests() {
    if [[ "$RUN_PYTHON_TESTS" != "true" ]]; then
        return 0
    fi

    log_info "Running Python unit tests..."

    local test_dir="$SCRIPT_DIR/unit/python"
    if [[ ! -d "$test_dir" ]]; then
        log_warning "Python unit test directory not found: $test_dir"
        return 0
    fi

    local test_files=()
    while IFS= read -r -d '' file; do
        test_files+=("$file")
    done < <(find "$test_dir" -name "test_*.py" -print0 2>/dev/null)

    if [[ ${#test_files[@]} -eq 0 ]]; then
        log_warning "No Python test files found"
        return 0
    fi

    # CRITICAL: Create isolated test workspace
    local test_workspace=$(mktemp -d -t songbird_tests_XXXXXX)
    local original_cwd=$(pwd)

    # Ensure cleanup happens no matter what
    trap "cd '$original_cwd'; rm -rf '$test_workspace'" EXIT

    # Change to the test workspace - this prevents any relative path writes to project root
    cd "$test_workspace"

    # Set up Python path to include project root for imports
    export PYTHONPATH="$PROJECT_ROOT:${PYTHONPATH:-}"

    # Fixed: Properly build Python command
    local python_cmd=("python3" "-m" "unittest" "discover" "-s" "$test_dir" "-p" "test_*.py")

    if [[ "$VERBOSE_OUTPUT" == "true" ]]; then
        python_cmd+=("-v")
    fi

    if [[ "$FAIL_FAST" == "true" ]]; then
        python_cmd+=("--failfast")
    fi

    # Run tests with or without coverage
    if [[ "$GENERATE_COVERAGE" == "true" ]]; then
        log_info "  Running with coverage analysis..."

        local coverage_cmd=("python3" "-m" "coverage" "run" "--source=$PROJECT_ROOT" "-m" "unittest" "discover" "-s" "$test_dir" "-p" "test_*.py")

        if [[ "$VERBOSE_OUTPUT" == "true" ]]; then
            coverage_cmd+=("-v")
        fi

        if [[ "$FAIL_FAST" == "true" ]]; then
            coverage_cmd+=("--failfast")
        fi

        if "${coverage_cmd[@]}" > "$TEST_RESULTS_DIR/python_unit_tests.log" 2>&1; then
            log_success "✅ Python unit tests passed"

            # Generate coverage report (from the test workspace)
            python3 -m coverage report > "$COVERAGE_DIR/python_coverage.txt"
            python3 -m coverage html -d "$COVERAGE_DIR/html"

            log_info "Coverage report generated: $COVERAGE_DIR/html/index.html"
        else
            log_error "❌ Python unit tests failed"
            if [[ "$VERBOSE_OUTPUT" == "true" ]]; then
                cat "$TEST_RESULTS_DIR/python_unit_tests.log"
            fi
            return 1
        fi
    else
        if "${python_cmd[@]}" > "$TEST_RESULTS_DIR/python_unit_tests.log" 2>&1; then
            log_success "✅ Python unit tests passed"
        else
            log_error "❌ Python unit tests failed"
            if [[ "$VERBOSE_OUTPUT" == "true" ]]; then
                cat "$TEST_RESULTS_DIR/python_unit_tests.log"
            fi
            return 1
        fi
    fi
}

# Run integration tests with workspace isolation
run_integration_tests() {
    if [[ "$RUN_INTEGRATION_TESTS" != "true" ]]; then
        return 0
    fi

    log_info "Running integration tests..."

    local test_dir="$SCRIPT_DIR/integration"
    if [[ ! -d "$test_dir" ]]; then
        log_warning "Integration test directory not found: $test_dir"
        return 0
    fi

    # Create isolated workspace for integration tests too
    local test_workspace=$(mktemp -d -t songbird_integration_XXXXXX)
    local original_cwd=$(pwd)

    trap "cd '$original_cwd'; rm -rf '$test_workspace'" EXIT

    cd "$test_workspace"

    export PYTHONPATH="$PROJECT_ROOT:${PYTHONPATH:-}"

    local python_options=()
    if [[ "$VERBOSE_OUTPUT" == "true" ]]; then
        python_options+=(-v)
    fi

    if [[ "$FAIL_FAST" == "true" ]]; then
        python_options+=(--failfast)
    fi

    if python3 -m unittest discover \
       -s "$test_dir" -p "test_*.py" ${python_options[@]+\"${python_options[@]}\"} \
       > "$TEST_RESULTS_DIR/integration_tests.log" 2>&1; then

        log_success "✅ Integration tests passed"
    else
        log_error "❌ Integration tests failed"
        if [[ "$VERBOSE_OUTPUT" == "true" ]]; then
            cat "$TEST_RESULTS_DIR/integration_tests.log"
        fi
        return 1
    fi
}

# Main execution function
main() {
    parse_arguments "$@"

    log_info "Starting Songbird test execution..."
    log_info "Working directory isolation: ENABLED"

    setup_test_environment

    local test_failures=0

    # Run unit tests
    if [[ "$RUN_UNIT_TESTS" == "true" ]]; then
        if [[ "$RUN_BASH_TESTS" == "true" ]]; then
            if ! run_bash_unit_tests; then
                ((test_failures++))
            fi
        fi

        if [[ "$RUN_PYTHON_TESTS" == "true" ]]; then
            if ! run_python_unit_tests; then
                ((test_failures++))
            fi
        fi
    fi

    # Run integration tests
    if [[ "$RUN_INTEGRATION_TESTS" == "true" ]]; then
        if ! run_integration_tests; then
            ((test_failures++))
        fi
    fi

    # Final results
    if [[ $test_failures -eq 0 ]]; then
        log_success "🎉 All tests completed successfully!"
        exit 0
    else
        log_error "❌ $test_failures test suite(s) failed"
        exit 1
    fi
}

# Execute main function
main "$@"