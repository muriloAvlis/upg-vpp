.PHONY: install-hooks checkstyle ci-build image install retest test e2e retest-e2e buildenv \
version

# Working directory
WORKDIR := $(CURDIR)
CONTAINER_NAME=upg-dev
DEV_IMAGE=upg-dev-env
DEV_USER_PATH=/home/dev

SHELL = /bin/bash
BUILD_TYPE ?= debug
IMAGE_BASE ?= upg
TEST_VERBOSITY ?= 2
VERSION = $(shell . hack/version.sh && echo "$${UPG_GIT_VERSION}")
include vpp.spec

install-hooks:
	hack/install-hooks.sh

# avoid rebuilding part of the source each time
version:
	ver_tmp=`mktemp version-XXXXXXXX`; \
	echo "#ifndef UPG_VERSION" >"$${ver_tmp}"; \
	echo "#define UPG_VERSION \"$(VERSION)\"" >>"$${ver_tmp}"; \
	echo "#endif" >>"$${ver_tmp}"; \
	if ! cmp upf/version.h "$${ver_tmp}"; then \
	  mv "$${ver_tmp}" upf/version.h; \
	else \
	  rm -f "$${ver_tmp}"; \
	fi

checkstyle:
	git ls-files | grep -e "\\.[c|h]$$" | xargs clang-format-11 -n --Werror

ci-build: version
	hack/ci-build.sh

image: version
	DOCKER_BUILDKIT=1 \
	docker build -t $(IMAGE_BASE):${BUILD_TYPE} \
	  --build-arg BUILD_TYPE=${BUILD_TYPE} \
	  --build-arg BASE=$(VPP_IMAGE_BASE)_${BUILD_TYPE} \
	  --build-arg DEVBASE=$(VPP_IMAGE_BASE)_dev_$(BUILD_TYPE) .

install: version
	hack/buildenv.sh hack/build-internal.sh install

retest:
	hack/buildenv.sh hack/run-integration-tests-internal.sh

test: version
	hack/buildenv.sh /bin/bash -c \
	  'make install && hack/run-integration-tests-internal.sh'

e2e: version
	UPG_BUILDENV_PRIVILEGED=1 hack/buildenv.sh /bin/bash -c \
	  'make install && hack/e2e.sh'

retest-e2e:
	UPG_BUILDENV_PRIVILEGED=1 hack/buildenv.sh hack/e2e.sh

buildenv: version
	UPG_BUILDENV_PRIVILEGED=1 hack/buildenv.sh

clean-buildenv:
	hack/buildenv.sh clean

genbinapi:
	hack/buildenv.sh /bin/bash -c 'make install && hack/genbinapi.sh'

# Open VSCode attached to buildenv container
code:
	DEVENV_BG=1 UPG_BUILDENV_PRIVILEGED=1 hack/buildenv.sh
	ENCNAME=`printf {\"containerName\":\"/vpp-build-$(BUILD_TYPE)-bg\"} | od -A n -t x1 | tr -d '[\n\t ]'`; \
	code --folder-uri "vscode-remote://attached-container+$${ENCNAME}/src"

build-dev-image:
	@echo "Building dev image '${DEV_IMAGE}'..."
	@docker build -t ${DEV_IMAGE} --build-arg VPP_DEV_IMAGE_BASE=${VPP_DEV_IMAGE_BASE} -f Dockerfile.dev .

run-dev-env:
	@echo "Starting dev container '${CONTAINER_NAME}'..."
	@docker rm -f ${CONTAINER_NAME} 2>/dev/null || true
	@docker container run -d \
		--name ${CONTAINER_NAME} \
		-v ${WORKDIR}:${DEV_USER_PATH}/workspace \
		-v ~/.ssh:${DEV_USER_PATH}/.ssh:ro \
		-w ${DEV_USER_PATH}/workspace \
		--hostname dev-upg \
		${DEV_IMAGE}

# Exec into dev container
exec-dev-env:
	@docker exec -it ${CONTAINER_NAME} bash

# Stop and remove dev container
stop-dev-env:
	@docker stop ${CONTAINER_NAME} || true
	@docker rm ${CONTAINER_NAME} || true