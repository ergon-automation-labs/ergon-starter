# Contributing to Bot Army Starter

Thanks for helping improve Bot Army! This guide covers contributing to the starter distribution tool and the broader Bot Army ecosystem.

## 🚀 Business Opportunities

Interested in building a business on top of Bot Army? Check out [BUSINESS_OPPORTUNITIES.md](./BUSINESS_OPPORTUNITIES.md) for detailed paths:

- **Domain-specific bot packs** (code quality, lead intelligence, content automation)
- **Hosted / SaaS offerings** (managed deployment, white-label dashboards)
- **Specialized bots** (single-purpose solutions)
- **Templates & scaffolding** (accelerators for common use cases)
- **Consulting & integration** (custom implementations, staff training)
- **Extensions & integrations** (connectors, plugins, API integrations)

Includes concrete examples for **Product & Engineering** and **Sales & Marketing** use cases.

## How to Contribute

### 1. Improve the Starter (this repo)

**Documentation & Guides:**
- Fix typos, clarify setup instructions
- Add platform-specific guides (Windows WSL2, Linux distributions, etc.)
- Improve wizard flow or error messages
- Add troubleshooting sections

**Features & Bug Fixes:**
- Enhance the interactive wizard
- Add new packs or bot selections
- Improve docker-compose generation
- Fix build or deployment issues
- Cross-platform improvements (macOS, Linux, Windows)

**Testing:**
- Test on different machines and OSes
- Report bugs with steps to reproduce
- Test new bots in the starter flow

### 2. Build and Publish a Bot

If you've built a bot for Bot Army:

1. **Build locally** using [ergon-bot-standard](https://github.com/ergon-automation-labs/ergon-bot-standard) or [ergon-bot-minimal](https://github.com/ergon-automation-labs/ergon-bot-minimal)

2. **Test with the starter:**
   ```bash
   # Clone your bot into repos/
   git clone <your-bot-repo> repos/your-bot
   
   # Add to docker-compose.yml manually and test
   docker compose up
   ```

3. **Submit a PR** to add your bot to the starter:
   - Add bot metadata to `catalog/bots.json`
   - Ensure repo is public with Apache 2.0 license
   - Add to a pack in `catalog/packs.json`
   - Include a README in your bot repo

4. **Reference:** See [main CONTRIBUTING](https://github.com/ergon-automation-labs/ergon-starter/blob/main/CONTRIBUTING.md) for ecosystem guidelines

### 3. Create or Improve Packs

Packs bundle related bots for different use cases:
- **Primary:** User-facing bots (GTD, dispatcher, synapse)
- **Background:** LLM, learning, domain bots
- **Infrastructure:** Support services (feeds, backups, skills)
- **Development:** Libraries for local editing

To propose a new pack:
1. Create a PR with the pack definition in `catalog/packs.json`
2. Include which bots belong in it and why
3. Update wizard documentation if needed

## Getting Started

### Running the Starter Locally

```bash
git clone https://github.com/ergon-automation-labs/ergon-starter.git
cd ergon-starter

# Test the wizard
make quickstart

# Or run individual steps
make init        # Interactive setup
make build       # Build the CLI
```

### Testing on Different OSes

- **macOS**: `make quickstart` (native)
- **Linux**: `make quickstart` (Docker)
- **Windows**: WSL2 + Docker Desktop, then `make quickstart`

Report OS-specific issues with your setup details.

### Code Style

**Go (CLI):**
- Format with `gofmt`
- Keep functions focused and well-named
- Add comments for non-obvious logic

**Shell Scripts:**
- Use `#!/bin/bash` for POSIX compatibility
- Quote variables
- Fail fast on errors (`set -e`)

**Documentation:**
- Keep README.md up to date
- Document new CLI commands
- Add troubleshooting sections

## Submitting Changes

1. **Fork & branch:** Create a feature branch from `main`
2. **Test thoroughly:** Test on at least one platform (macOS, Linux, or Windows with WSL2)
3. **Commit clearly:** Use descriptive commit messages
4. **Open a PR:** Reference any related issues
5. **Respond to review:** We'll iterate together

### PR Checklist

- [ ] Tested locally (wizard completes, bots start)
- [ ] Updated docs if needed
- [ ] Commit message is clear
- [ ] No hardcoded paths or secrets
- [ ] Works on multiple platforms (if applicable)

## Reporting Issues

**Starter issues:** File here with:
- Your OS and Docker version
- Steps to reproduce
- Full error output
- What you expected to happen

**Individual bot issues:** File in that bot's repo (e.g., `ergon-gtd`)

**Ecosystem questions:** Use [GitHub Discussions](https://github.com/ergon-automation-labs/ergon-starter/discussions)

## License

All contributions must be Apache 2.0 compatible. Bots added to the starter must include a LICENSE file.

---

**Questions?** Check the [main Bot Army docs](https://github.com/ergon-automation-labs/ergon-starter) or open a Discussion.

**Want your bot featured?** Once it's stable and tested, submit a PR to add it to `catalog/bots.json` and the appropriate pack.
