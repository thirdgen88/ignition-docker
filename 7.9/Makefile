export SHELL=bash
export IGNITION_VERSION=$$(set -eo pipefail; grep IGNITION_VERSION= Dockerfile | cut -d'=' -f 2- | sed 's/"//g')
export IGNITION_VERSION_CHECK=if [ -z "$(IGNITION_VERSION)" ]; then exit 1; fi

.build: .build-full .build-edge
.build-full:
	@echo "======== BUILDING IGNITION FULL IMAGE LOCALLY (SINGLE ARCHITECTURE) ========"
	$(IGNITION_VERSION_CHECK)
	echo docker build ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} -t $(BASE_IMAGE_NAME):$(IGNITION_VERSION) -f Dockerfile .
.build-edge:
	@echo "======== BUILDING IGNITION EDGE IMAGE LOCALLY (SINGLE ARCHITECTURE) ========"
	$(IGNITION_VERSION_CHECK)
	echo docker build ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} --build-arg BUILD_EDITION=EDGE -t $(BASE_IMAGE_NAME):$(IGNITION_VERSION)-edge -f Dockerfile .	

.multibuild: .multibuild-full .multibuild-edge
.multibuild-full:
	@echo "======== BUILDING IGNITION FULL IMAGE AND PUSHING TO DOCKER HUB (MULTI ARCHITECTURE) ========"
	$(IGNITION_VERSION_CHECK)
	echo docker buildx build ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} -t $(BASE_IMAGE_NAME):$(IGNITION_VERSION) --platform=${DOCKER_MULTI_ARCH} -f Dockerfile . --push
	echo docker buildx imagetools create $(BASE_IMAGE_NAME):$(IGNITION_VERSION) --tag $(BASE_IMAGE_NAME):7.9
.multibuild-edge:
	@echo "======== BUILDING IGNITION EDGE IMAGE AND PUSHING TO DOCKER HUB (MULTI ARCHITECTURE) ========"
	$(IGNITION_VERSION_CHECK)
	echo docker buildx build ${DOCKER_BUILD_OPTS} ${DOCKER_BUILD_ARGS} --build-arg BUILD_EDITION=EDGE -t $(BASE_IMAGE_NAME):$(IGNITION_VERSION)-edge --platform=${DOCKER_MULTI_ARCH} -f Dockerfile . --push
	echo docker buildx imagetools create $(BASE_IMAGE_NAME):$(IGNITION_VERSION) --tag $(BASE_IMAGE_NAME):7.9-edge

push-registry:
	@echo "======== PUSHING AND TAGGING IMAGES TO DOCKER HUB ========"
	echo docker tag $(BASE_IMAGE_NAME):$(IGNITION_VERSION) $(BASE_IMAGE_NAME):7.9
	echo docker push $(BASE_IMAGE_NAME):7.9

build: .build
multibuild: .multibuild