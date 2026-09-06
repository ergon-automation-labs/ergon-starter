# Vagrant Install Test — Bot Army Starter

Reproduces the **fresh-user experience** of the documented headless install
inside a clean Ubuntu 24.04 ARM64 VM (Parallels provider), so we can observe
exactly where the install works, where it breaks, and what a fix requires.

## What is being tested

The exact one-liner from the README, unmodified, piped from GitHub `main`:

```
curl -fsSL https://raw.githubusercontent.com/ergon-automation-labs/ergon-starter/main/install.sh | bash -s -- --default
```

The bootstrap provisioning **deliberately does not install Docker** —
`install.sh` is supposed to handle that itself, and testing that path is the
point.

## Workflow

```bash
vagrant up                        # create VM + bootstrap (git/curl/python3/make only)

vagrant ssh                       # session 1
./01-install-real.sh              # pristine flow — surfaces the pitfalls

exit; vagrant ssh                 # session 2 (fresh login — see pitfall P1)
./02-install-fixed.sh             # workarounds → should reach a running army
./03-verify.sh                    # health checks + PASS/FAIL verdict

vagrant destroy -f                # when done
```

Logs land in `~/logs/` inside the VM and are mirrored to `vagrant-test/logs/`
via the synced folder.

## Services reachable from the Mac

| Service   | URL / port                    |
|-----------|-------------------------------|
| NATS      | `nats://localhost:54222`      |
| Monitor   | http://localhost:58222        |
| Postgres  | `localhost:55432` (pgvector)  |
| Ollama    | http://localhost:51434        |
| MCP       | http://localhost:39900/mcp    |

## Pitfalls found (updated as the test runs)

See `PITFALLS.md`.