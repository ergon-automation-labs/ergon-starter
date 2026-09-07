# Auditor Pack Design

**Purpose:** Bot Army as a self-service operability audit platform. Client mounts their repo, selects their LLM harness, and gets measurable proof of repo operability improvements across Phase 0→1→2.

## Pack Overview

```
ORIGINAL 6 BOTS (Foundation)
┌─────────────────────────────────────────────────┐
│  repo_scanner_bot (mount + analyze)             │
│  test_runner_bot (measure suite)                │
│  llm_harness_bot (code generation)              │
│  baseline_bot (stores metrics)                  │
│  metrics_collector_bot (duration/coverage)      │
│  report_generator_bot (exportable proof)        │
└─────────────────────────────────────────────────┘
                           ↓
CRITICAL 4 BOTS (Methodology Implementation) ⭐
┌─────────────────────────────────────────────────┐
│  measurement_executor_bot ⭐                     │
│    → Runs agent on codebase, measures           │
│      time/tokens/proposal quality               │
│                                                 │
│  documentation_validator_bot ⭐                 │
│    → Audits CLAUDE.md, docstrings, topology     │
│      completeness & currency                    │
│                                                 │
│  code_alignment_bot ⭐                          │
│    → Detects where code ≠ documentation         │
│      (module boundaries, type specs, clarity)   │
│                                                 │
│  phase_comparator_bot ⭐                        │
│    → Compares Phase 0→1→2 metrics               │
│      (time improvement, token cost, confidence) │
└─────────────────────────────────────────────────┘
```

## The Measurement Model

**Grounded in the Agent-Operable Repo Contract consulting methodology:**

- **Phase 0 (Baseline):** Codebase as-is. Agent explores architecture. Measure: time-to-task-completion, tokens consumed, proposal quality, false starts, confidence level.
- **Phase 1 (Documentation):** Add CLAUDE.md, topology diagram, docstrings. Re-run same task. Measure improvement.
- **Phase 2 (Code Alignment):** Fix code structure to match docs (type specs, module ownership, boundaries). Re-run. Measure again.

**Real-world result (Plausible Analytics):** 82.5% faster exploration, same token cost, higher confidence by Phase 2.

## Bots in the Pack

### 1. `repo_scanner_bot`
**Purpose:** Analyze client repo structure and test config

**Inputs:**
- Mounted repo path (`/workspace/<client_repo>`)
- Language detection

**Outputs:**
- Repo structure JSON
- Test framework (pytest, Jest, mix test, etc.)
- Dockerfile / build config
- CI/CD pipeline (if any)

**Subjects:**
- `auditor.repo.scan` → returns metadata
- `auditor.repo.lint` → code quality baseline

### 2. `test_runner_bot`
**Purpose:** Execute test suite, measure timing and failures

**Inputs:**
- Repo path + test command
- Number of runs (for averaging)
- Parallelization hints

**Outputs:**
- Test duration (total, per-test)
- Pass/fail counts
- Coverage %
- Failure patterns

**Subjects:**
- `auditor.test.run` → starts suite
- `auditor.test.status` → live progress
- `auditor.test.result` → final metrics

### 3. `llm_harness_bot`
**Purpose:** Integrate user's LLM provider; generate optimizations

**Inputs:**
- LLM config (Claude -p / Code / API key + model)
- Test failures + code
- Optimization goal (speed / coverage)

**Outputs:**
- Suggested improvements (parallelization, smart selection, etc.)
- Refactored code snippets
- Risk assessment ("this change breaks X")

**Subjects:**
- `auditor.llm.optimize` → ask for improvements
- `auditor.llm.validate` → check if suggestion is safe
- `auditor.llm.apply` → (optional) apply changes

### 4. `metrics_collector_bot`
**Purpose:** Record and aggregate test metrics over time

**Inputs:**
- Test results (duration, coverage, pass/fail)
- Timestamp, git commit hash
- Optimization applied (yes/no, which)

**Outputs:**
- Time-series metrics (JSON + CSV)
- Trends (% improvement over time)
- Outlier detection (sudden slowness)

**Subjects:**
- `auditor.metrics.record` → store a run
- `auditor.metrics.query` → fetch trends
- `auditor.metrics.export` → CSV/JSON for reports

### 5. `baseline_bot`
**Purpose:** Store baseline (before) metrics for comparison

**Inputs:**
- Initial test run (no optimizations)
- Client repo metadata

**Outputs:**
- Baseline record (duration, coverage, etc.)
- Baseline version (git commit, timestamp)

**Subjects:**
- `auditor.baseline.set` → establish baseline
- `auditor.baseline.get` → fetch it for comparison
- `auditor.baseline.reset` → start fresh after major refactor

### 6. `report_generator_bot`
**Purpose:** Create executive reports showing improvements

**Inputs:**
- Baseline metrics
- Current metrics (after optimizations)
- Summary of changes applied

**Outputs:**
- HTML report (formatted, client-ready)
- JSON structured data
- CSV for Excel/BI tools
- Markdown for GitHub / documentation

**Subjects:**
- `auditor.report.generate` → create report
- `auditor.report.format` → pick format (html / json / csv / md)
- `auditor.report.export` → download

---

## Critical 4 Bots (Grounded in Consulting Methodology) ⭐

### 7. `measurement_executor_bot` ⭐ (TIER 1 - ESSENTIAL)

**Purpose:** Run the actual architectural task on the codebase and measure performance

**Why:** This IS the measurement. Everything else is context. The core methodology runs an agent through an architecture discovery task (e.g., "Map all services and their data flow") and captures:

**Inputs:**
- Repo path + architecture/language
- Task definition (e.g., "map services, identify data flow, suggest optimization")
- LLM provider config

**Outputs:**
- Time-to-completion (milliseconds)
- Tokens consumed (input + output)
- Proposal quality (agent-generated architecture, graded by rubric)
- False starts (direction changes, backtracking)
- Confidence level (agent's self-reported certainty)

**Subjects:**
- `auditor.measurement.phase0` → run on baseline codebase
- `auditor.measurement.phase1` → run after documentation added
- `auditor.measurement.phase2` → run after code alignment
- `auditor.measurement.result` → return {time, tokens, quality, false_starts, confidence}

**Storage:** PostgreSQL table per phase (phase0_measurements, phase1_measurements, phase2_measurements)

---

### 8. `documentation_validator_bot` ⭐ (TIER 1 - ESSENTIAL)

**Purpose:** Audit CLAUDE.md, docstrings, and topology completeness

**Why:** Phase 1 = add documentation. Need to measure "how complete is the documentation?" before/after Phase 1.

**Inputs:**
- Repo path
- Language (Elixir, Python, Rust, etc.)

**Outputs:**
- **CLAUDE.md audit:**
  - Exists? (yes/no)
  - Current? (modified within last N days)
  - Sections present: architecture, patterns, deployment, testing, PARA access, etc.
  - Quality score (0-100)

- **Docstring audit:**
  - % of public functions documented
  - % of modules documented
  - % of type specs defined (Elixir/Python/TypeScript)

- **Topology audit:**
  - Service map present? (diagram or markdown)
  - Data flow documented?
  - External dependencies listed?

- **Overall doc health score:** (0-100)

**Subjects:**
- `auditor.docs.scan` → analyze current state
- `auditor.docs.compare` → before/after Phase 1
- `auditor.docs.report` → formatted audit results

**Storage:** PostgreSQL table (documentation_audits) with per-repo baseline, Phase 1, Phase 2

---

### 9. `code_alignment_bot` ⭐ (TIER 1 - ESSENTIAL)

**Purpose:** Detect where code structure doesn't match documentation

**Why:** Phase 2 = align code to docs. Need to identify misalignments so client knows what to fix.

**Inputs:**
- Repo path
- Documentation from documentation_validator_bot (or fresh scan)
- Language

**Outputs:**
- **Detected misalignments:**
  - Module owns functionality that's claimed to be elsewhere
  - Data flow in code differs from topology doc
  - Type specs missing/incomplete where docs claim they exist
  - Interfaces unclear (which functions are public vs internal?)
  - Code organization doesn't match described architecture

- **Per-misalignment:**
  - Severity (critical, high, medium, low)
  - Location (file:line)
  - Evidence (what the code does vs what docs claim)
  - Suggested fix (brief)

- **Alignment score:** % of claimed behavior that's actually reflected in code

**Subjects:**
- `auditor.alignment.scan` → analyze codebase
- `auditor.alignment.report` → list misalignments
- `auditor.alignment.diff` → before/after Phase 2

**Storage:** PostgreSQL table (code_alignment_findings) with severity/location/phase

---

### 10. `phase_comparator_bot` ⭐ (TIER 1 - ESSENTIAL)

**Purpose:** Compare Phase 0→1→2 metrics and show improvement

**Why:** The value prop = concrete before/after proof. Show the client: "Here's what Phase 1 documentation achieved."

**Inputs:**
- Phase 0 measurement (from measurement_executor_bot)
- Phase 1 measurement (after doc audit / Phase 1 work)
- Phase 2 measurement (after code alignment / Phase 2 work)
- Documentation audit results (all phases)
- Code alignment findings (all phases)

**Outputs:**
- **Comparison table:**
  ```
  Metric                Phase 0    Phase 1    Phase 2    Improvement
  ────────────────────────────────────────────────────────────────
  Time-to-task (min)    12.3       8.1        2.8        77% faster
  Tokens consumed       2,847      2,891      2,840      ~same cost
  Proposal quality      72%        84%        91%        +19pts
  False starts          4          1          0          90% fewer
  Confidence level      6.2/10     8.1/10     9.3/10     +50% higher
  Doc completeness %    45%        92%        95%        +50pts
  Code alignment %      62%        78%        94%        +32pts
  ```

- **Executive summary:**
  ```
  Documentation (Phase 1) reduced exploration time by 34% with no token cost.
  Code alignment (Phase 2) further reduced time by 65% and increased confidence.
  Total improvement: 77% faster exploration, +19 points quality, 90% fewer false starts.
  ```

- **Actionable recommendations:**
  - Which Phase 1 docs were highest-impact?
  - Which Phase 2 code fixes had best ROI?
  - What should this team prioritize next?

**Subjects:**
- `auditor.comparison.generate` → trigger report
- `auditor.comparison.export` → return {phase0, phase1, phase2, deltas}

**Storage:** PostgreSQL table (phase_comparisons) with normalized metrics per repo

---

## Wizard Flow (When Setting Up Auditor Pack)

### Step 1: Audit Type
```
┌─────────────────────────────────────────┐
│ What do you want to audit?              │
├─────────────────────────────────────────┤
│  ○ Single repo (one-time)               │
│  ○ Ongoing monitoring (weekly/monthly)  │
│  ○ Before/after (improvement tracking)  │
│  ○ Multiple repos (fleet audit)         │
└─────────────────────────────────────────┘
```

### Step 2: Repo Selection
```
┌─────────────────────────────────────────┐
│ Where is your code?                     │
├─────────────────────────────────────────┤
│ Repo path: [_____________________]      │
│           (local mount or GitHub URL)   │
│                                         │
│ Or upload a .tar.gz: [Browse...]       │
└─────────────────────────────────────────┘
```

**Validation:**
- Check repo structure (tests exist?)
- Detect language/framework

### Step 3: LLM Configuration
```
┌─────────────────────────────────────────┐
│ Which coding assistant?                 │
├─────────────────────────────────────────┤
│  ○ Claude (via claude.ai/code)          │
│    API Key: [_________________]         │
│    Model:   [claude-opus-5  ▼]         │
│                                         │
│  ○ Claude Pro (web / mobile)            │
│    (manual intervention for each step)  │
│                                         │
│  ○ OpenAI GPT-4                         │
│    API Key: [_________________]         │
│                                         │
│  ○ None (just run tests, no LLM)        │
│    (measure baseline only)              │
└─────────────────────────────────────────┘
```

### Step 4: Success Criteria
```
┌─────────────────────────────────────────┐
│ What does "better" look like?           │
├─────────────────────────────────────────┤
│ Test suite duration target:             │
│   Current: [auto-detected from scan]    │
│   Goal:    [_________] minutes          │
│                                         │
│ Code coverage target:                   │
│   Current: [auto-detected]%             │
│   Goal:    [___]%                       │
│                                         │
│ Test failure tolerance:                 │
│   ○ Zero (all must pass)                │
│   ○ Flaky tests OK (< 5% failure rate)  │
│   ○ Optimize for speed (ignore failures)│
└─────────────────────────────────────────┘
```

### Step 5: Audit Schedule
```
┌─────────────────────────────────────────┐
│ How often to audit?                     │
├─────────────────────────────────────────┤
│  ○ One time (now)                       │
│  ○ Weekly (every Monday 9am)            │
│  ○ Monthly (1st of month)               │
│  ○ After each commit (CI/CD hook)       │
│  ○ Manual only (on-demand)              │
│                                         │
│ Notifications:                          │
│  ☑ Email report                         │
│  ☑ Slack #ops                           │
│  ☑ GitHub PR comment                    │
└─────────────────────────────────────────┘
```

### Step 6: Report Preferences
```
┌─────────────────────────────────────────┐
│ How to deliver results?                 │
├─────────────────────────────────────────┤
│ Formats:                                │
│  ☑ HTML (for web/email)                 │
│  ☑ JSON (for automation)                │
│  ☑ CSV (for spreadsheets)               │
│  ☑ Markdown (for GitHub)                │
│                                         │
│ Report includes:                        │
│  ☑ Baseline comparison                  │
│  ☑ Suggested optimizations              │
│  ☑ Risk assessment                      │
│  ☑ Detailed metrics                     │
│  ☑ Executive summary                    │
│                                         │
│ Public link (read-only):                │
│  ○ Enabled (share results)              │
│  ○ Disabled (private)                   │
└─────────────────────────────────────────┘
```

### Step 7: Review & Confirm
```
┌─────────────────────────────────────────┐
│ Audit Configuration                     │
├─────────────────────────────────────────┤
│ Type:          Before/After Tracking    │
│ Repo:          /workspace/my-app        │
│ Language:      Python (detected)        │
│ LLM:           Claude Opus 5            │
│ Target:        30m → 10m test suite     │
│ Coverage:      80% → 85%                │
│ Schedule:      Weekly (Mondays 9am)     │
│ Reports:       HTML + JSON + CSV        │
│ Notifications: Email + Slack            │
│                                         │
│           [Cancel]    [Start Audit]     │
└─────────────────────────────────────────┘
```

---

## Wizard-Driven Bot Configuration

For each bot, the wizard populates `.env` + `override.yml`:

### `repo_scanner_bot`
```yaml
AUDITOR_REPO_PATH: /workspace/my-app
AUDITOR_LANGUAGE: python
AUDITOR_TEST_FRAMEWORK: pytest
```

### `test_runner_bot`
```yaml
AUDITOR_TEST_COMMAND: "pytest -v --cov"
AUDITOR_TEST_RUNS: 3  # average
AUDITOR_PARALLELISM: 4
```

### `llm_harness_bot`
```yaml
LLM_PROVIDER: claude
LLM_API_KEY: sk-ant-...
LLM_MODEL: claude-opus-5
AUDITOR_OPTIMIZATION_GOAL: speed  # or: coverage
```

### `baseline_bot`
```yaml
AUDITOR_BASELINE_DURATION: "45m30s"
AUDITOR_BASELINE_COVERAGE: "78.5%"
AUDITOR_BASELINE_COMMIT: "abc1234def"
```

### `metrics_collector_bot`
```yaml
AUDITOR_METRICS_RETENTION: 90  # days
AUDITOR_EXPORT_FORMATS: "html,json,csv"
```

### `report_generator_bot`
```yaml
AUDITOR_REPORT_THEME: professional  # or: minimal
AUDITOR_PUBLIC_LINK: true
AUDITOR_NOTIFICATIONS: "email,slack,github"
```

### `measurement_executor_bot` (NEW)
```yaml
AUDITOR_TASK_DEFINITION: "map_services"  # or: architecture_discovery
AUDITOR_LLM_PROVIDER: claude
AUDITOR_PHASE: "phase0"  # updated per measurement run
```

### `documentation_validator_bot` (NEW)
```yaml
AUDITOR_DOC_LANGUAGES: "elixir,python,typescript"
AUDITOR_TYPE_SPEC_REQUIRED: true
AUDITOR_DOCSTRING_THRESHOLD: 80  # % minimum
```

### `code_alignment_bot` (NEW)
```yaml
AUDITOR_SEVERITY_FILTER: "critical,high"  # only report these
AUDITOR_ALIGNMENT_BASELINE: "phase0"  # compare against
```

### `phase_comparator_bot` (NEW)
```yaml
AUDITOR_COMPARISON_FORMAT: "json"  # or: html, markdown
AUDITOR_EXPORT_DELTAS: true  # include before/after diffs
AUDITOR_RECOMMENDATIONS_LLM: claude  # generate insights
```

---

## End-to-End Flow (Phases 0→1→2)

**Day 1: User runs installer**
```bash
curl ... | bash -s -- --pack auditor
# Wizard guides through 7 steps
# Bot Army boots with Auditor pack + critical 4 configured
```

**Phase 0: Baseline**
```
repo_scanner_bot → detects structure
     ↓
documentation_validator_bot → scan current docs (likely minimal)
     ↓
code_alignment_bot → scan current code-vs-docs alignment
     ↓
measurement_executor_bot → run agent on codebase (PHASE 0)
     → captures: time, tokens, proposal quality, false starts, confidence
     ↓
baseline_bot → stores Phase 0 snapshot
     ↓
metrics_collector_bot → record Phase 0 baseline
```

**Phase 1: Add Documentation**
```
(User adds/improves: CLAUDE.md, topology, docstrings)
     ↓
documentation_validator_bot → re-scan (should show improvement)
     ↓
measurement_executor_bot → run same agent task (PHASE 1)
     → captures: time, tokens, proposal quality, false starts, confidence
     ↓
metrics_collector_bot → record Phase 1 results
```

**Phase 2: Align Code to Docs**
```
code_alignment_bot → identify what to fix (from Phase 1 docs)
     ↓
(User: add type specs, fix module ownership, clarify boundaries)
     ↓
code_alignment_bot → re-scan (should show resolution)
     ↓
measurement_executor_bot → run same agent task (PHASE 2)
     → captures: time, tokens, proposal quality, false starts, confidence
     ↓
metrics_collector_bot → record Phase 2 results
     ↓
phase_comparator_bot → generate Phase 0→1→2 comparison report
     ↓
report_generator_bot → format for client (HTML/JSON/Markdown)
     ↓
Notify user: "You achieved 77% faster exploration, +19 quality points"
```

**Week 1 → Week 4: Tracking**
```
Baseline:      test_suite: 45m, coverage: 78%
After opt 1:   test_suite: 38m, coverage: 79%  (+15% speed)
After opt 2:   test_suite: 28m, coverage: 82%  (+38% speed, +5% coverage)
After opt 3:   test_suite: 12m, coverage: 85%  (+73% speed, +9% coverage)

Report: "You've achieved 73% faster tests. Estimated savings: $X/month in CI costs."
```

---

## Integration Points

**With Bot Army ecosystem:**
- Stores metrics in shared PostgreSQL
- Posts results to NATS (observable by other bots)
- Exports to bridge for GTD task creation ("Fix X test suite slowness")

**With external systems:**
- GitHub: PR comments, commit status checks
- Slack: notifications, report links
- Email: scheduled digests
- Datadog/Grafana: export metrics for dashboards

---

## Why This Matters for Consulting

**Client Perspective:**
- ✅ Concrete proof of improvement (not consultant opinion)
- ✅ Self-service (don't need consultant for every check)
- ✅ Measurable (test duration in minutes, not vibes)
- ✅ Repeatable (run audit weekly to track progress)

**Consultant Perspective:**
- ✅ Client retention (they keep re-running audits)
- ✅ Outcome proof (show before/after in pitch)
- ✅ Scalable (one bot pack, many clients)
- ✅ Data-driven billing (charge per optimization milestone)

**For Bot Army:**
- ✅ Proves operability methodology in action
- ✅ Case study material (partner case studies)
- ✅ Upsell opportunity (from "audit" to "continuous improvement")
