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

## Private pack repos (gh token)

Most pack bots live in **public** `ergon-automation-labs` repos and clone fine
over anonymous HTTPS. Some packs — currently the **sre** pack (`ergon_sre`) —
live in **private** repos. Cloning them needs one of:

- `gh` installed in the VM and authenticated with a token of an
  **`ergon-automation-labs` member** (contents:read on the repo suffices —
  no need for the personal CLI token's full scope):

  ```bash
  # inside the VM (arm64 binary on this VM)
  curl -sL https://github.com/cli/cli/releases/latest/download/gh_*_linux_arm64.tar.gz | tar -xz -C /tmp
  sudo mv /tmp/gh_*_linux_arm64/bin/gh /usr/local/bin/
  gh auth login --with-token   # paste a member's PAT
  ```

- or a **pre-seeded clone**: from an authenticated host, `git clone --depth 1
  git@github.com:ergon-automation-labs/ergon_sre.git` into the combo dir's
  `repos/bot_army_sre`. The harness tolerates ff-pull refresh failures on
  private repos (warning, keeps the seeded copy — it just won't auto-refresh).

Catalog entries mark this with `"visibility": "private"`. The generator warns
upfront when a private-repo pack is selected without gh auth, and a failed
clone now prints the diagnosis + fix instead of a bare `could not read
Username for 'https://github.com'`.

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