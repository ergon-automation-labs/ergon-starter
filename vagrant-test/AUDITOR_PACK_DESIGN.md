# Auditor Pack Design

**Purpose:** Bot Army as a self-service operability audit platform. Client mounts their repo, selects their LLM harness, and gets measurable proof of test efficiency improvements.

## Pack Overview

```
┌─────────────────────────────────────────────────┐
│           AUDITOR PACK (6 bots)                 │
├─────────────────────────────────────────────────┤
│                                                 │
│  repo_scanner_bot ──┐                          │
│  (mount + analyze)  │                          │
│                     ├──→ audit_orchestrator_bot│
│  test_runner_bot ───┤    (coordinates tests)   │
│  (measure suite)    │                          │
│                     ├──→ metrics_collector_bot │
│  llm_harness_bot ───┤    (duration/coverage)   │
│  (code generation)  │                          │
│                     ├──→ comparator_bot        │
│  baseline_bot ──────┤    (before/after)        │
│  (stores metrics)   │                          │
│                     └──→ report_generator_bot  │
│                         (exportable proof)     │
└─────────────────────────────────────────────────┘
```

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

---

## End-to-End Flow

**Day 1: User runs installer**
```bash
curl ... | bash -s -- --pack auditor
# Wizard guides through 7 steps
# Bot Army boots with Auditor pack configured
```

**Audit runs (automated or on-demand)**
```
repo_scanner_bot → detects structure
     ↓
baseline_bot → establishes baseline (if first run)
     ↓
test_runner_bot → measures initial suite
     ↓
llm_harness_bot → suggests optimizations
     ↓
(User reviews suggestions, optionally applies them)
     ↓
test_runner_bot → re-measure suite
     ↓
metrics_collector_bot → record delta
     ↓
report_generator_bot → create report
     ↓
Notify user (email/Slack/GitHub)
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
