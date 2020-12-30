export SHELL=bash
# The expression below ensures that an IGNITION_VERSION is defined in the Dockerfile
export IGNITION_VERSION=$$(set -eo pipefail; grep IGNITION_VERSION= Dockerfile | cut -d'=' -f 2- | sed 's/"//g')
# This version check leverages the above and aborts the build if not found
export IGNITION_VERSION_CHECK=if [ -z "${IGNITION_VERSION}" ]; then exit 1; fi
# Pull in base options (if called from this directory)
include ../.env

.build:
	@echo "======== BUILDING IGNITION IMAGE LOCALLY (SINGLE ARCHITECTURE) ========"
	$(IGNITION_VERSION_CHECK)
	docker build ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} --build-arg BUILD_EDITION=STABLE -t ${BASE_IMAGE_NAME}:${IGNITION_VERSION} -f Dockerfile .

.build-nightly:
	@echo "======== BUILDING IGNITION NIGHTLY IMAGE LOCALLY (SINGLE ARCHITECTURE) ========"
	$(IGNITION_VERSION_CHECK)
	docker build ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} --build-arg BUILD_EDITION=NIGHTLY -t ${BASE_IMAGE_NAME}:nightly -f Dockerfile .

.multibuild: CACHE_TAG=cache-${IGNITION_VERSION}
.multibuild:
	@echo "======== BUILDING IGNITION IMAGE AND PUSHING TO REGISTRY (MULTI ARCHITECTURE) ========"
	$(IGNITION_VERSION_CHECK)
	docker buildx build ${DOCKER_BUILDX_CACHE_OPTS} ${DOCKER_BUILDX_OPTS} ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} --build-arg BUILD_EDITION=STABLE -t ${BASE_IMAGE_NAME}:${IGNITION_VERSION} --platform=${DOCKER_MULTI_ARCH} -f Dockerfile . --push
	docker buildx imagetools create ${BASE_IMAGE_NAME}:${IGNITION_VERSION} --tag ${BASE_IMAGE_NAME}:8.1
	docker buildx imagetools create ${BASE_IMAGE_NAME}:${IGNITION_VERSION} --tag ${BASE_IMAGE_NAME}:latest

.multibuild-nightly:
	@echo "======== BUILDING IGNITION NIGHTLY IMAGE AND PUSHING TO REGISTRY (MULTI ARCHITECTURE) ========"
	docker buildx build ${DOCKER_BUILDX_OPTS} ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} --build-arg BUILD_EDITION=NIGHTLY -t ${BASE_IMAGE_NAME}:nightly --platform=${DOCKER_MULTI_ARCH} -f Dockerfile . --push

.push-registry:
	@echo "======== PUSHING AND TAGGING IMAGES TO REGISTRY ========"
	docker push ${BASE_IMAGE_NAME}:${IGNITION_VERSION}
	docker tag ${BASE_IMAGE_NAME}:${IGNITION_VERSION} ${BASE_IMAGE_NAME}:8.1
	docker push ${BASE_IMAGE_NAME}:8.1
	docker tag ${BASE_IMAGE_NAME}:${IGNITION_VERSION} ${BASE_IMAGE_NAME}:latest
	docker push ${BASE_IMAGE_NAME}:latest

### BUILD TARGETS ###
all:
	@echo "Please specify a build target: build, multibuild, build-nightly, multibuild-nightly"
build: .build
build-nightly: .build-nightly
multibuild: .multibuild
multibuild-nightly: .multibuild-nightly
