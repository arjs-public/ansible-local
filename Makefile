#
# docker Makefile -- combine some usefull stuff
#

.PHONY: help boot shutdown destroy stats status destroy plugins images fetch destroyi startup teardown construct cleanup wipeout list create delete
SHELL := /bin/bash

# --------- Defaults

DOCKERHOST = dockerhost
ENV = develop
CONFIG_F = config.xml.j2
PLUGIN_F = plugins.ini
BASE_D = .
PB_D = $(BASE_D)/playbooks/$(DOCKERHOST)
TAG_D = $(BASE_D)/roles/$(DOCKERHOST)/files
CNFG_D = $(BASE_D)/roles/$(DOCKERHOST)/defaults
FILES_D = $(BASE_D)/roles/$(DOCKERHOST)/files
A_CFG = $(BASE_D)/configs/ansible.cfg

ifeq ($(wildcard $(CNFG_D)/envs/$(APP)/$(ENV).json),)
CONFIGS =
else
CONFIGS = -e "@$(CNFG_D)/envs/$(APP)/$(ENV).json"
endif

# --------- Rules

help:
	@echo "-- Help ---------"
	@echo "* make APP=<app folder> *) [ENV=<environment> *)] ((boot | shutdown | destroy) [EXTRAS=<ansible-playbook params>]) | stats)"
	@echo "* make INFRA=<infra name from list>  [ENV=<environment> *)] startup | teardown | construct | cleanup"
	@echo "* make ENV=<Environment name> *) PORT=<Port extension to use> **) create | [DELETE=true ***)] delete"
	@echo "* make TAG=<Dockerfile folder> build"
	@echo "* make IMG=<image from dockerhub> fetch"
	@echo "* make IMG=<image from images> *) destroyi"
	@echo "* make status | images | list | wipeout ***)"
	@echo
	@echo "*) see 'make list' output for available options; default: ENV = develop"
	@echo "**) Port extension to use with normal prefix 80 or db prefix 90; e.g. normal (80) + extenison (85) = port (8085)"
	@echo "***) Very dangerous, since deletes all associated folders on 'dockerhost'"
	@echo "****) Very dangerous, since it kills all docker containers on 'dockerhost'"
	@echo
	@echo "-- Defaults ---------"
	@echo "* ENV = $(ENV)"
	@echo "* TAG_D = $(TAG_D)"
	@echo "* CNFG_D = $(CNFG_D)"
	@echo "* FILES_D = $(FILES_D)"
	@echo "* A_CFG = $(A_CFG)"

# -------- Playbook handling

verify_playbook:
	$(eval PLAYBOOKPATH=$(PB_D)/$(PLAYBOOK).yml)
	@test -f $(PLAYBOOKPATH) || (echo "Error: No playbook found!" && exit 1)

execute: verify_playbook
	@echo
	@echo "--- Execute playbook '$(PLAYBOOK)'  ------------------------"
ifeq ($(origin APP), undefined)
	$(eval APPIMG=)
else
	$(eval APPIMG=-e "image=$(APP)")
endif
ifeq ($(wildcard $(A_CFG)),)
	@echo ansible-playbook $(PLAYBOOKPATH) $(APPIMG) $(CONFIGS) $(EXTRAS)
else
	ANSIBLE_CONFIG=$(A_CFG) ansible-playbook $(PLAYBOOKPATH) $(APPIMG) $(CONFIGS) $(EXTRAS)
endif
	@echo

# -------- Application handling

verify:
	@test "$(APP)" && test -d $(CNFG_D)/envs/$(APP)/ || (echo "Error: APP not set or APP folder not found! ($(CNFG_D)/envs/$(APP)/" && exit 1)
	@test "$(ENV)" && test -s $(CNFG_D)/envs/$(APP)/$(ENV).json || (echo "Error: ENV not set or ENV json not found! ($(CNFG_D)/envs/$(APP)/$(ENV).json)" && exit 1)

extras:
	[[ -f $(FILES_D)/$(APP)/$(CONFIG_F) ]] && make APP=$(APP) ENV=$(ENV) configs
	[[ -f $(CNFG_D)/envs/$(APP)/$(PLUGIN_F) ]] && make APP=$(APP) ENV=$(ENV) plugins
	@echo "--- Boot done ------------------------"
	@echo

boot: PLAYBOOK=start
boot: verify extras execute stats status
	@echo "--- Boot done ------------------------"
	@echo

shutdown: PLAYBOOK=stop
shutdown: verify stats execute status
	@echo "--- Shutdown done ------------------------"
	@echo

destroy: PLAYBOOK=remove
destroy: verify stats execute status
	@echo "--- Destroy done ------------------------"
	@echo

stats: verify
	@echo "--- Stats ------------------------"
	@[[ `docker ps | grep $(APP)_$(ENV)` ]] && docker logs --tail="30" $(APP)_$(ENV) || echo No stats available
	@echo

status:
	@echo "--- Status ------------------------"
	@docker ps -a
	@echo

plugins: PLAYBOOK=plugins
plugins: verify execute
	@echo "--- Plugins done ------------------------"
	@echo

configs: PLAYBOOK=configs
configs: verify execute
	@echo "--- Configs done ------------------------"
	@echo

# -------- Environment handling

verify_env:
	@test "$(ENV)" || (echo "Error: ENV not set!" && exit 1)

verify_port:
	@test "$(PORT)" || (echo "Error: PORT not set!" && exit 1)

create: ENV=
create: PLAYBOOK=create
create: EXTRAS += -e "env_name=$(ENV)" -e "port=$(PORT)"
create: verify_env verify_port verify_playbook execute
	@echo "--- Create done ------------------------"
	@echo

delete: ENV=
delete: DELETE=False
delete: PLAYBOOK=delete
delete: EXTRAS += -e "env_name=$(ENV)" -e "clean_up=$(DELETE)"
delete: verify_env verify_playbook execute
	@echo "--- Delete done ------------------------"
	@echo

# -------- Image handling

verify_tag:
	$(eval CONFIGS=)
	$(eval APP=$(TAG))
	@test "$(APP)" && test -d $(TAG_D)/$(TAG)/ || (echo "Error: TAG not set or TAG folder not found! ($(TAG_D)/$(TAG)/)" && exit 1)

build: PLAYBOOK=build
build: verify_tag verify_playbook execute
	@echo "--- Build done ------------------------"
	@echo

images:
	@docker images

verify_img:
	@test "$(IMG)" || (echo "Error: IMG not set!" && exit 1)

fetch: verify_img
	@docker pull ${IMG}

destroyi: verify_img
	@docker rmi ${IMG}

# -------- Wipe.out or debugging

wipeout:
	@echo "--- Wipeout ------------------------"
	@for j in $$(docker ps -a -q); \
	do \
		echo Removing $$j; \
		docker stop $$j; \
		docker rm $$j; \
		echo; \
	done
	@docker ps -a

# -------- Infra handling

verify_infra:
	@test "$(INFRA)" && test -s $(CNFG_D)/infra/$(INFRA).txt || (echo "Error: INFRA not set or INFRA txt not found! ($(CNFG_D)/infra/$(INFRA).txt)" && exit 1)

startup: verify_infra
	@echo "--- Startup '$(INFRA)' ------------------------"
	@for l in `cat $(CNFG_D)/infra/$(INFRA).txt`; \
	do \
		echo "----- Booting $$l ------------------------"; \
		[[ -f $(FILES_D)/$$l/$(CONFIG_F) ]] && make APP=$$l ENV=$(ENV) configs; \
		[[ -f $(CNFG_D)/envs/$$l/$(PLUGIN_F) ]] && make APP=$$l ENV=$(ENV) plugins; \
		make APP=$$l ENV=$(ENV) boot; \
		echo; \
	done
	@docker ps -a

teardown: verify_infra
	@echo "--- Teardown '$(INFRA)' -----------------------"
	@for l in `tac $(CNFG_D)/infra/$(INFRA).txt`; \
	do \
		echo Shuting down $$l; \
		make APP=$$l ENV=$(ENV) shutdown; \
		echo; \
	done
	@docker ps -a

construct: verify_infra
	@echo "--- Construct '$(INFRA)' ------------------------"
	@for l in `cat $(CNFG_D)/infra/$(INFRA).txt`; \
	do \
		echo Building $$l; \
		make TAG=$$l build; \
		echo; \
	done
	@docker images

cleanup: verify_infra
	@echo "--- Cleanup '$(INFRA)' ------------------------"
	@for l in `cat $(CNFG_D)/infra/$(INFRA).txt`; \
	do \
		echo Removing $$l; \
		make APP=$$l ENV=$(ENV) destroy; \
		echo; \
	done
	@echo "--- Cleanup '$(INFRA)' done ------------------------"

list:
	@echo "--- List Infrastructures [$(CNFG_D)/infra/] ------------------------"
	@pushd $(CNFG_D)/infra/ > /dev/null; ls -1 *.txt | cut -d _ -f 2 | cut -d . -f 1; popd > /dev/null
	@echo
	@echo "--- List Application Stacks [$(CNFG_D)/envs/] ------------------------"
	@pushd $(CNFG_D)/envs/ > /dev/null; ls -1dR */; popd > /dev/null
	@echo
	@echo "--- List Environments in Application Stacks [$(CNFG_D)/envs/] ------------------------"
	@pushd $(CNFG_D)/envs/ > /dev/null; ls -1dR **/*.json | cut -d / -f 2 | cut -d . -f 1 | sort -u; popd > /dev/null
	@echo
	@echo "--- List Custom Docker Images [$(TAG_D)] ------------------------"
	@pushd $(TAG_D) > /dev/null; ls -1dR */; popd > /dev/null
	@echo
