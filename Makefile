# Options
export DOCKER_CLI_EXPERIMENTAL=enabled
export BASE_IMAGE_NAME=kcollins/ignition

# Global Docker Build Args/Options
export DOCKER_BUILD_OPTS=
export DOCKER_BUILD_ARGS=

# Architecture Definitions
export DOCKER_MULTI_ARCH=linux/arm,linux/amd64

# Build Docker Images (Local)
.build: .build-8.0
.build-7.9:
	cd 7.9; make build;
.build-8.0:
	cd 8.0; make build;

# Build and Push Multi-Arch Docker Image
.multibuild: .multibuild-8.0
.multibuild-7.9:
	cd 7.9; make multibuild;
.multibuild-8.0:
	cd 8.0; make multibuild;
.multibuild-nightly:
	cd 8.0; make multibuild-nightly;

# Summary Targets
all: build
build: .build
multibuild: .multibuild
multibuild-nightly: .multibuild-nightly
