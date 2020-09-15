export SHELL=bash
# The expression below ensures that an IGNITION_VERSION is defined in the Dockerfile
export IGNITION_VERSION=$$(set -eo pipefail; grep IGNITION_VERSION= Dockerfile | cut -d'=' -f 2- | sed 's/"//g')
# This version check leverages the above and aborts the build if not found
export IGNITION_VERSION_CHECK=if [ -z "${IGNITION_VERSION}" ]; then exit 1; fi
# Pull in base options (if called from this directory)
include ../.env

.build-nightly:
	@echo "======== BUILDING IGNITION NIGHTLY IMAGE LOCALLY (SINGLE ARCHITECTURE) ========"
	$(IGNITION_VERSION_CHECK)
	docker build ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} --no-cache --build-arg BUILD_EDITION=NIGHTLY -t ${BASE_IMAGE_NAME}:nightly -f Dockerfile .

.multibuild-nightly: CACHE_TAG=cache-nightly
.multibuild-nightly:
	@echo "======== BUILDING IGNITION NIGHTLY IMAGE AND PUSHING TO REGISTRY (MULTI ARCHITECTURE) ========"
	docker buildx build ${DOCKER_BUILDX_OPTS} ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} --build-arg BUILD_EDITION=NIGHTLY -t ${BASE_IMAGE_NAME}:nightly --platform=${DOCKER_MULTI_ARCH} -f Dockerfile . --push

### BUILD TARGETS ###
all:
	@echo "Please specify a build target: build-nightly, multibuild-nightly"
build-nightly: .build-nightly
multibuild-nightly: .multibuild-nightly
