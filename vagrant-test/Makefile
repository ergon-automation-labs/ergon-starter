# Convenience driver for the Vagrant-based Bot Army Starter install test.
#
#   make up           create + bootstrap the VM (NO docker — install.sh owns that)
#   make phase1       pristine documented install, unmodified  → surfaces pitfalls
#   make phase2       fixed flow in a FRESH ssh session        → should reach running army
#   make verify       health checks + PASS/FAIL verdict
#   make phase04      bot pack matrix validation (test each pack in isolation)
#   make phase04-pack test a specific pack (PACK=Primary)
#   make all          phase1 → phase2 → verify → phase04, one command
#
# Each `vagrant ssh -c` spawns a NEW login session — that is exactly the P1
# workaround (docker group membership only applies to fresh sessions).

.PHONY: help up ssh phase1 phase2 verify phase04 phase04-pack all status dashboard watch-02 watch-03 watch-04 watch-all logs halt destroy clean

help:
	@echo "Bot Army Starter — Vagrant install-test driver"
	@echo ""
	@echo "  make up              create + bootstrap the VM"
	@echo "  make ssh             shell into the VM"
	@echo ""
	@echo "Phases (run these from the vagrant-test directory):"
	@echo "  make phase1          pristine documented install (surfaces pitfalls)"
	@echo "  make phase2          fixed install (fresh session = P1 workaround)"
	@echo "  make verify          deployment health checks + verdict"
	@echo "  make phase04         test all bot packs in isolation"
	@echo "  make phase04-pack    test one pack (PACK=Primary)"
	@echo "  make all             up → phase1 → phase2 → verify → phase04"
	@echo ""
	@echo "Watch progress (from host, no ssh needed):"
	@echo "  make dashboard       show phase status at a glance"
	@echo "  make watch-02        live tail of phase 02 + docker logs"
	@echo "  make watch-04        live tail of phase 04 + docker logs"
	@echo "  make watch-all       live tail of all logs"
	@echo ""
	@echo "VM admin:"
	@echo "  make status          VM + compose status"
	@echo "  make logs            tail phase logs from the VM"
	@echo "  make halt            suspend the VM"
	@echo "  make destroy         destroy the VM"
	@echo "  make clean           destroy + wipe logs/.vagrant"

up:
	vagrant up --provider=parallels

ssh:
	vagrant ssh

phase1:
	vagrant ssh -c "bash ./01-install-real.sh" 2>&1 | tee logs/01-stream.txt

phase2:
	vagrant ssh -c "bash ./02-install-fixed.sh" 2>&1 | tee logs/02-install-fixed.log

verify:
	vagrant ssh -c "bash ./03-verify.sh" 2>&1 | tee logs/03-verify.log

phase04:
	vagrant ssh -c "bash ./scripts/04-pack-matrix.sh" 2>&1 | tee logs/04-pack-matrix.log

phase04-pack:
	@if [ -z "$(PACK)" ]; then echo "Usage: make phase04-pack PACK=Primary"; exit 1; fi
	vagrant ssh -c "PACK=$(PACK) bash ./scripts/04-pack-matrix.sh" 2>&1 | tee logs/04-pack-$(PACK).log

all: up phase1 phase2 verify phase04

dashboard:
	bash ./dashboard.sh

watch-02:
	bash ./watch-all.sh 02

watch-03:
	bash ./watch-all.sh 03

watch-04:
	bash ./watch-all.sh 04

watch-all:
	bash ./watch-all.sh all

status:
	vagrant status
	vagrant ssh -c "cd ~/bot-army 2>/dev/null && docker compose ps || docker ps -a"

logs:
	vagrant ssh -c "tail -n 30 ~/logs/*.log"

halt:
	vagrant halt

destroy:
	vagrant destroy -f

clean: destroy
	rm -rf logs .vagrant