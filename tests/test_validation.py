"""Production validation test runner.

This file enables pytest-bdd to discover and execute Gherkin scenarios.
Each feature file is automatically mapped to test functions via pytest-bdd.
"""

from pytest_bdd import scenarios

# Load all scenarios from feature files
scenarios("features/health.feature")
scenarios("features/authentication.feature")
scenarios("features/olts.feature")
scenarios("features/onus_read.feature")
scenarios("features/onus_write.feature")
scenarios("features/profiles.feature")
scenarios("features/services.feature")
