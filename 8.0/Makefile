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

.multibuild: CACHE_TAG=cache-${IGNITION_VERSION}
.multibuild:
	@echo "======== BUILDING IGNITION IMAGE AND PUSHING TO REGISTRY (MULTI ARCHITECTURE) ========"
	$(IGNITION_VERSION_CHECK)
	docker buildx build ${DOCKER_BUILDX_OPTS} ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} --build-arg BUILD_EDITION=STABLE -t ${BASE_IMAGE_NAME}:${IGNITION_VERSION} --platform=${DOCKER_MULTI_ARCH} -f Dockerfile . --push
	docker buildx imagetools create ${BASE_IMAGE_NAME}:${IGNITION_VERSION} --tag ${BASE_IMAGE_NAME}:8.0
	docker buildx imagetools create ${BASE_IMAGE_NAME}:${IGNITION_VERSION} --tag ${BASE_IMAGE_NAME}:latest

.push-registry:
	@echo "======== PUSHING AND TAGGING IMAGES TO REGISTRY ========"
	docker push ${BASE_IMAGE_NAME}:${IGNITION_VERSION}
	docker tag ${BASE_IMAGE_NAME}:${IGNITION_VERSION} ${BASE_IMAGE_NAME}:8.0
	docker push ${BASE_IMAGE_NAME}:8.0
	docker tag ${BASE_IMAGE_NAME}:${IGNITION_VERSION} ${BASE_IMAGE_NAME}:latest
	docker push ${BASE_IMAGE_NAME}:latest

### BUILD TARGETS ###
all:
	@echo "Please specify a build target: build, multibuild"
build: .build
multibuild: .multibuild
push-registry: .push-registry