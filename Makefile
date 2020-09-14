# Global Options
include .env

# Build Docker Images (Local)
.build: .build-7.9 .build-8.0
.build-7.9:
	cd 7.9; make build;
.build-8.0:
	cd 8.0; make build;
.build-nightly:
	cd 8.1; make build-nightly;

# Build and Push Multi-Arch Docker Image to Registry
.multibuild: .multibuild-7.9 .multibuild-8.0
.multibuild-7.9:
	cd 7.9; make multibuild;
.multibuild-8.0:
	cd 8.0; make multibuild;
.multibuild-nightly:
	cd 8.1; make multibuild-nightly;

# Summary Targets
all:
	@echo "Please specify a build target: build, build-nightly, multibuild, multibuild-nightly"
build: .build
build-nightly: .build-nightly
multibuild: .multibuild
multibuild-nightly: .multibuild-nightly
