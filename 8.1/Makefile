export SHELL=bash
# The expression below ensures that an IGNITION_VERSION is defined in the Dockerfile
export IGNITION_VERSION=$$(grep -Po '(?<=IGNITION_VERSION=\")((\d\.){2}\d+)(?=\")' Dockerfile)
# This version check leverages the above and aborts the build if not found
export IGNITION_VERSION_CHECK=if [ -z "${IGNITION_VERSION}" ]; then exit 1; fi
# Extract the IGNITION_RC_VERSION for release candidate, if applicable
IGNITION_RC_VERSION:=$$(grep -Po '(?<=IGNITION_RC_VERSION=\")((\d\.){2}\d+-rc\d)(?=\")' Dockerfile)
# Pull in base options (if called from this directory)
include ../.env

.build-full:
	@echo "======== BUILDING IGNITION IMAGE LOCALLY (SINGLE ARCHITECTURE) ========"
	$(IGNITION_VERSION_CHECK)
	docker build ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} \
		--build-arg BUILD_EDITION=STABLE \
		-t ${BASE_IMAGE_NAME}:${IGNITION_VERSION} -f Dockerfile .

.build-slim:
	@echo "======== BUILDING IGNITION SLIM IMAGE LOCALLY (SINGLE ARCHITECTURE) ========"
	$(IGNITION_VERSION_CHECK)
	docker build ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} \
		--build-arg BUILD_EDITION=STABLE \
		--build-arg ZIP_EXCLUSION_RESOURCE_LIST=designerlauncher,perspectiveworkstation,visionclientlauncher \
		--build-arg ZIP_EXCLUSION_ARCHITECTURE_LIST=mac,linux64,win64 \
		-t ${BASE_IMAGE_NAME}:${IGNITION_VERSION}-slim -f Dockerfile .

.build-full-rc:
	@if [[ -n "${IGNITION_RC_VERSION}" ]]; then \
		echo "======== BUILDING IGNITION RELEASE CANDIDATE IMAGE LOCALLY (SINGLE ARCHITECTURE) ========"; \
		docker build ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} \
		--build-arg BUILD_EDITION=RC \
		-t ${BASE_IMAGE_NAME}:${IGNITION_RC_VERSION} -f Dockerfile .; \
	else \
		echo "======== SKIPPING IGNITION RELEASE CANDIDATE IMAGE (SINGLE ARCHITECTURE) ========"; \
	fi

.build-slim-rc:
	@if [[ -n "${IGNITION_RC_VERSION}" ]]; then \
		echo "======== BUILDING IGNITION RELEASE CANDIDATE SLIM IMAGE LOCALLY (SINGLE ARCHITECTURE) ========"; \
		docker build ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} \
		--build-arg BUILD_EDITION=RC \
		--build-arg ZIP_EXCLUSION_RESOURCE_LIST=designerlauncher,perspectiveworkstation,visionclientlauncher \
		--build-arg ZIP_EXCLUSION_ARCHITECTURE_LIST=mac,linux64,win64 \
		-t ${BASE_IMAGE_NAME}:${IGNITION_RC_VERSION}-slim -f Dockerfile .; \
	else \
		echo "======== SKIPPING IGNITION RELEASE CANDIDATE IMAGE (SINGLE ARCHITECTURE) ========"; \
	fi

.build-full-nightly:
	@echo "======== BUILDING IGNITION NIGHTLY IMAGE LOCALLY (SINGLE ARCHITECTURE) ========"
	$(IGNITION_VERSION_CHECK)
	docker build ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} \
		--build-arg BUILD_EDITION=NIGHTLY \
		-t ${BASE_IMAGE_NAME}:nightly -f Dockerfile .

.build-slim-nightly:
	@echo "======== BUILDING IGNITION NIGHTLY SLIM IMAGE LOCALLY (SINGLE ARCHITECTURE) ========"
	$(IGNITION_VERSION_CHECK)
	docker build ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} \
		--build-arg BUILD_EDITION=NIGHTLY \
		--build-arg ZIP_EXCLUSION_RESOURCE_LIST=designerlauncher,perspectiveworkstation,visionclientlauncher \
		--build-arg ZIP_EXCLUSION_ARCHITECTURE_LIST=mac,linux64,win64 \
		-t ${BASE_IMAGE_NAME}:nightly-slim -f Dockerfile .

.multibuild-full: CACHE_TAG=cache-${IGNITION_VERSION}
.multibuild-full:
	@echo "======== BUILDING IGNITION IMAGE AND PUSHING TO REGISTRY (MULTI ARCHITECTURE) ========"
	$(IGNITION_VERSION_CHECK)
	docker buildx build ${DOCKER_BUILDX_CACHE_OPTS} ${DOCKER_BUILDX_OPTS} ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} \
		--build-arg BUILD_EDITION=STABLE \
		-t ${BASE_IMAGE_NAME}:${IGNITION_VERSION} --platform=${DOCKER_MULTI_ARCH} -f Dockerfile . --push
	docker buildx imagetools create ${BASE_IMAGE_NAME}:${IGNITION_VERSION} --tag ${BASE_IMAGE_NAME}:8.1
	docker buildx imagetools create ${BASE_IMAGE_NAME}:${IGNITION_VERSION} --tag ${BASE_IMAGE_NAME}:latest

.multibuild-slim: CACHE_TAG=cache-${IGNITION_VERSION}-slim
.multibuild-slim:
	@echo "======== BUILDING IGNITION SLIM IMAGE AND PUSHING TO REGISTRY (MULTI ARCHITECTURE) ========"
	$(IGNITION_VERSION_CHECK)
	docker buildx build ${DOCKER_BUILDX_CACHE_OPTS} ${DOCKER_BUILDX_OPTS} ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} \
		--build-arg BUILD_EDITION=STABLE \
		--build-arg ZIP_EXCLUSION_RESOURCE_LIST=designerlauncher,perspectiveworkstation,visionclientlauncher \
		--build-arg ZIP_EXCLUSION_ARCHITECTURE_LIST=mac,linux64,win64 \
		-t ${BASE_IMAGE_NAME}:${IGNITION_VERSION}-slim --platform=${DOCKER_MULTI_ARCH} -f Dockerfile . --push
	docker buildx imagetools create ${BASE_IMAGE_NAME}:${IGNITION_VERSION}-slim --tag ${BASE_IMAGE_NAME}:8.1-slim
	docker buildx imagetools create ${BASE_IMAGE_NAME}:${IGNITION_VERSION}-slim --tag ${BASE_IMAGE_NAME}:latest-slim

.multibuild-full-rc:
	@if [[ -n "${IGNITION_RC_VERSION}" ]]; then \
		echo "======== BUILDING IGNITION RELEASE CANDIDATE IMAGE AND PUSHING TO REGISTRY (MULTI ARCHITECTURE) ========"; \
		docker buildx build ${DOCKER_BUILDX_OPTS} ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} \
			--build-arg BUILD_EDITION=RC \
			-t ${BASE_IMAGE_NAME}:${IGNITION_RC_VERSION} --platform=${DOCKER_MULTI_ARCH} -f Dockerfile . --push; \
	else \
		echo "======== SKIPPING IGNITION RELEASE CANDIDATE IMAGE (MULTI ARCHITECTURE) ========"; \
	fi

.multibuild-slim-rc:
	@if [[ -n "${IGNITION_RC_VERSION}" ]]; then \
		echo "======== BUILDING IGNITION RELEASE CANDIDATE SLIM IMAGE AND PUSHING TO REGISTRY (MULTI ARCHITECTURE) ========"; \
		docker buildx build ${DOCKER_BUILDX_OPTS} ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} \
			--build-arg BUILD_EDITION=RC \
			--build-arg ZIP_EXCLUSION_RESOURCE_LIST=designerlauncher,perspectiveworkstation,visionclientlauncher \
			--build-arg ZIP_EXCLUSION_ARCHITECTURE_LIST=mac,linux64,win64 \
			-t ${BASE_IMAGE_NAME}:${IGNITION_RC_VERSION}-slim --platform=${DOCKER_MULTI_ARCH} -f Dockerfile . --push; \
	else \
		echo "======== SKIPPING IGNITION RELEASE CANDIDATE IMAGE (MULTI ARCHITECTURE) ========"; \
	fi

.multibuild-full-nightly:
	@echo "======== BUILDING IGNITION NIGHTLY IMAGE AND PUSHING TO REGISTRY (MULTI ARCHITECTURE) ========"
	docker buildx build ${DOCKER_BUILDX_OPTS} ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} \
		--build-arg BUILD_EDITION=NIGHTLY \
		-t ${BASE_IMAGE_NAME}:nightly --platform=${DOCKER_MULTI_ARCH} -f Dockerfile . --push

.multibuild-slim-nightly:
	@echo "======== BUILDING IGNITION NIGHTLY SLIM IMAGE AND PUSHING TO REGISTRY (MULTI ARCHITECTURE) ========"
	docker buildx build ${DOCKER_BUILDX_OPTS} ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} \
		--build-arg BUILD_EDITION=NIGHTLY \
		--build-arg ZIP_EXCLUSION_RESOURCE_LIST=designerlauncher,perspectiveworkstation,visionclientlauncher \
		--build-arg ZIP_EXCLUSION_ARCHITECTURE_LIST=mac,linux64,win64 \
		-t ${BASE_IMAGE_NAME}:nightly-slim --platform=${DOCKER_MULTI_ARCH} -f Dockerfile . --push

.push-registry:
	@echo "======== PUSHING AND TAGGING IMAGES TO REGISTRY ========"
	docker push ${BASE_IMAGE_NAME}:${IGNITION_VERSION}
	docker push ${BASE_IMAGE_NAME}:${IGNITION_VERSION}-slim
	docker tag ${BASE_IMAGE_NAME}:${IGNITION_VERSION} ${BASE_IMAGE_NAME}:8.1
	docker tag ${BASE_IMAGE_NAME}:${IGNITION_VERSION}-slim ${BASE_IMAGE_NAME}:8.1-slim
	docker push ${BASE_IMAGE_NAME}:8.1
	docker push ${BASE_IMAGE_NAME}:8.1-slim
	docker tag ${BASE_IMAGE_NAME}:${IGNITION_VERSION} ${BASE_IMAGE_NAME}:latest
	docker tag ${BASE_IMAGE_NAME}:${IGNITION_VERSION}-slim ${BASE_IMAGE_NAME}:latest-slim
	docker push ${BASE_IMAGE_NAME}:latest
	docker push ${BASE_IMAGE_NAME}:latest-slim
	@if [[ -n "${IGNITION_RC_VERSION}" ]]; then \
		docker push ${BASE_IMAGE_NAME}:${IGNITION_RC_VERSION} \
		docker push ${BASE_IMAGE_NAME}:${IGNITION_RC_VERSION}-slim \
	fi

### BUILD TARGETS ###
all:
	@echo "Please specify a build target: [build | multibuild][-full | -slim][-rc | -nightly]"
build: .build-full .build-slim
build-full: .build-full
build-slim: .build-slim
build-rc: .build-full-rc .build-slim-rc
build-full-rc: .build-full-rc
build-slim-rc: .build-slim-rc
build-nightly: .build-full-nightly .build-slim-nightly
build-full-nightly: .build-full-nightly
build-slim-nightly: .build-slim-nightly
multibuild: .multibuild-full .multibuild-slim
multibuild-full: .multibuild-full
multibuild-slim: .multibuild-slim
multibuild-rc: .multibuild-full-rc .multibuild-slim-rc
multibuild-full-rc: .multibuild-full-rc
multibuild-slim-rc: .multibuild-slim-rc
multibuild-nightly: .multibuild-full-nightly .multibuild-slim-nightly
multibuild-full-nightly: .multibuild-full-nightly
multibuild-slim-nightly: .multibuild-slim-nightly
