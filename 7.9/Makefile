export SHELL=bash
# The expression below ensures that an IGNITION_VERSION is defined in the Dockerfile
export IGNITION_VERSION=$$(set -eo pipefail; grep IGNITION_VERSION= Dockerfile | cut -d'=' -f 2- | sed 's/"//g')
# This version check leverages the above and aborts the build if not found
export IGNITION_VERSION_CHECK=if [ -z "${IGNITION_VERSION}" ]; then exit 1; fi
# Pull in base options (if called from this directory)
include ../.env

.build: .build-full .build-edge
.build-full:
	@echo "======== BUILDING IGNITION FULL IMAGE LOCALLY (SINGLE ARCHITECTURE) ========"
	$(IGNITION_VERSION_CHECK)
	docker build ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} --build-arg BUILD_EDITION=FULL -t ${BASE_IMAGE_NAME}:${IGNITION_VERSION} -f Dockerfile .
.build-edge:
	@echo "======== BUILDING IGNITION EDGE IMAGE LOCALLY (SINGLE ARCHITECTURE) ========"
	$(IGNITION_VERSION_CHECK)
	docker build ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} --build-arg BUILD_EDITION=EDGE -t ${BASE_IMAGE_NAME}:${IGNITION_VERSION}-edge -f Dockerfile .	

.multibuild: .multibuild-full .multibuild-edge
.multibuild-full: CACHE_TAG=cache-${IGNITION_VERSION}
.multibuild-full:
	@echo "======== BUILDING IGNITION FULL IMAGE AND PUSHING TO REGISTRY (MULTI ARCHITECTURE) ========"
	$(IGNITION_VERSION_CHECK)
	docker buildx build ${DOCKER_BUILDX_CACHE_OPTS} ${DOCKER_BUILDX_OPTS} ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} --build-arg BUILD_EDITION=FULL -t ${BASE_IMAGE_NAME}:${IGNITION_VERSION} --platform=${DOCKER_MULTI_ARCH} -f Dockerfile . --push
	docker buildx imagetools create ${BASE_IMAGE_NAME}:${IGNITION_VERSION} --tag ${BASE_IMAGE_NAME}:7.9
.multibuild-edge: CACHE_TAG=cache-${IGNITION_VERSION}-edge
.multibuild-edge:
	@echo "======== BUILDING IGNITION EDGE IMAGE AND PUSHING TO REGISTRY (MULTI ARCHITECTURE) ========"
	$(IGNITION_VERSION_CHECK)
	docker buildx build ${DOCKER_BUILDX_CACHE_OPTS} ${DOCKER_BUILDX_OPTS} ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} --build-arg BUILD_EDITION=EDGE -t ${BASE_IMAGE_NAME}:${IGNITION_VERSION}-edge --platform=${DOCKER_MULTI_ARCH} -f Dockerfile . --push
	docker buildx imagetools create ${BASE_IMAGE_NAME}:${IGNITION_VERSION}-edge --tag ${BASE_IMAGE_NAME}:7.9-edge

.push-registry: .push-registry-full .push-registry-edge
.push-registry-full:
	@echo "======== PUSHING AND TAGGING FULL IMAGES TO REGISTRY ========"
	docker push ${BASE_IMAGE_NAME}:${IGNITION_VERSION}
	docker tag ${BASE_IMAGE_NAME}:${IGNITION_VERSION} ${BASE_IMAGE_NAME}:7.9
	docker push ${BASE_IMAGE_NAME}:7.9
.push-registry-edge:
	@echo "======== PUSHING AND TAGGING EDGE IMAGES TO REGISTRY ========"
	docker push ${BASE_IMAGE_NAME}:${IGNITION_VERSION}-edge
	docker tag ${BASE_IMAGE_NAME}:${IGNITION_VERSION}-edge ${BASE_IMAGE_NAME}:7.9-edge
	docker push ${BASE_IMAGE_NAME}:7.9-edge

### BUILD TARGETS ###
all:
	@echo "Please specify a build target: build, build-nightly, multibuild, multibuild-nightly"
build: .build
multibuild: .multibuild
push-registry: .push-registry