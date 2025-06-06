#!/bin/bash

# =============================================================================
# COVERAGE REPORT GENERATOR
# =============================================================================
#
# Generates coverage reports for both Bash and Python code.
# Integrates with test-runner.sh to provide coverage analysis.
#
# =============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly COVERAGE_DIR="$SCRIPT_DIR/coverage"

# Generate coverage report
generate_coverage_report()
{
    echo "📊 Generating comprehensive coverage report..."

    mkdir -p "$COVERAGE_DIR"

    # Run tests with coverage
    echo "Running tests with coverage analysis..."
    "$SCRIPT_DIR/test-runner.sh" --python-only --no-integration > /dev/null

    # Generate detailed reports
    echo "Generating HTML coverage report..."
    python3 -m coverage html -d "$COVERAGE_DIR/html"

    echo "Generating XML coverage report..."
    python3 -m coverage xml -o "$COVERAGE_DIR/coverage.xml"

    # Generate summary
    python3 -m coverage report > "$COVERAGE_DIR/coverage_summary.txt"

    echo "✅ Coverage reports generated:"
    echo "   HTML: $COVERAGE_DIR/html/index.html"
    echo "   XML:  $COVERAGE_DIR/coverage.xml"
    echo "   Text: $COVERAGE_DIR/coverage_summary.txt"
}

# Show coverage summary
show_coverage_summary()
{
    if [[ -f "$COVERAGE_DIR/coverage_summary.txt" ]]; then
        echo ""
        echo "📈 COVERAGE SUMMARY"
        echo "==================="
        cat "$COVERAGE_DIR/coverage_summary.txt"
    fi
}

main()
{
    generate_coverage_report
    show_coverage_summary
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi