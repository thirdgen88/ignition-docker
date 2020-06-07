export SHELL=bash
export IGNITION_VERSION=$$(set -eo pipefail; grep IGNITION_VERSION= Dockerfile | cut -d'=' -f 2- | sed 's/"//g')
export IGNITION_VERSION_CHECK=if [ -z "$(IGNITION_VERSION)" ]; then exit 1; fi
include ../.env

.build: .build-full .build-edge
.build-full:
	@echo "======== BUILDING IGNITION FULL IMAGE LOCALLY (SINGLE ARCHITECTURE) ========"
	$(IGNITION_VERSION_CHECK)
	docker build ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} -t $(BASE_IMAGE_NAME):$(IGNITION_VERSION) -f Dockerfile .
.build-edge:
	@echo "======== BUILDING IGNITION EDGE IMAGE LOCALLY (SINGLE ARCHITECTURE) ========"
	$(IGNITION_VERSION_CHECK)
	docker build ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} --build-arg BUILD_EDITION=EDGE -t $(BASE_IMAGE_NAME):$(IGNITION_VERSION)-edge -f Dockerfile .	

.multibuild: .multibuild-full .multibuild-edge
.multibuild-full:
	@echo "======== BUILDING IGNITION FULL IMAGE AND PUSHING TO DOCKER HUB (MULTI ARCHITECTURE) ========"
	$(IGNITION_VERSION_CHECK)
	docker buildx build ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} -t $(BASE_IMAGE_NAME):$(IGNITION_VERSION) --platform=${DOCKER_MULTI_ARCH} -f Dockerfile . --push
	docker buildx imagetools create $(BASE_IMAGE_NAME):$(IGNITION_VERSION) --tag $(BASE_IMAGE_NAME):8.0
	docker buildx imagetools create $(BASE_IMAGE_NAME):$(IGNITION_VERSION) --tag $(BASE_IMAGE_NAME):latest
.multibuild-edge:
	@echo "======== BUILDING IGNITION EDGE IMAGE AND PUSHING TO DOCKER HUB (MULTI ARCHITECTURE) ========"
	$(IGNITION_VERSION_CHECK)
	docker buildx build ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} --build-arg BUILD_EDITION=EDGE -t $(BASE_IMAGE_NAME):$(IGNITION_VERSION)-edge --platform=${DOCKER_MULTI_ARCH} -f Dockerfile . --push
	docker buildx imagetools create $(BASE_IMAGE_NAME):$(IGNITION_VERSION) --tag $(BASE_IMAGE_NAME):8.0-edge
	docker buildx imagetools create $(BASE_IMAGE_NAME):$(IGNITION_VERSION) --tag $(BASE_IMAGE_NAME):latest-edge
.multibuild-nightly: .multibuild-nightly-full .multibuild-nightly-edge
.multibuild-nightly-full:
	@echo "======== BUILDING IGNITION FULL NIGHTLY IMAGE AND PUSHING TO DOCKER HUB (MULTI ARCHITECTURE) ========"
	$(IGNITION_VERSION_CHECK)
	docker buildx build ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} --build-arg BUILD_EDITION=NIGHTLY_FULL -t $(BASE_IMAGE_NAME):nightly --platform=${DOCKER_MULTI_ARCH} -f Dockerfile . --push
.multibuild-nightly-edge:
	@echo "======== BUILDING IGNITION EDGE NIGHTLY IMAGE AND PUSHING TO DOCKER HUB (MULTI ARCHITECTURE) ========"
	$(IGNITION_VERSION_CHECK)
	docker buildx build ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} --build-arg BUILD_EDITION=NIGHTLY_EDGE -t $(BASE_IMAGE_NAME):nightly-edge --platform=${DOCKER_MULTI_ARCH} -f Dockerfile . --push

push-registry:
	@echo "======== PUSHING AND TAGGING IMAGES TO DOCKER HUB ========"
	docker push $(BASE_IMAGE_NAME):$(IGNITION_VERSION)
	docker tag $(BASE_IMAGE_NAME):$(IGNITION_VERSION) $(BASE_IMAGE_NAME):8.0
	docker push $(BASE_IMAGE_NAME):8.0
	docker tag $(BASE_IMAGE_NAME):$(IGNITION_VERSION) $(BASE_IMAGE_NAME):latest
	docker push $(BASE_IMAGE_NAME):latest

build: .build
multibuild: .multibuild
multibuild-nightly: .multibuild-nightly