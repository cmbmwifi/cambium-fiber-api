"""Production validation test runner.

This file enables pytest-bdd to discover and execute Gherkin scenarios.
Each feature file is automatically mapped to test functions via pytest-bdd.
"""

import os
import sys

from pytest_bdd import scenarios

# Ensure step definitions are importable
sys.path.insert(0, os.path.dirname(__file__))
from steps.production_steps import *  # noqa: F403

# Load all scenarios from feature files
scenarios("health.feature")
scenarios("authentication.feature")
scenarios("olts.feature")
scenarios("onus_read.feature")
scenarios("onus_write.feature")
scenarios("profiles.feature")
scenarios("services.feature")
scenarios("z_rate_limiting.feature")  # Must run LAST - blocks localhost OAuth for 10s
