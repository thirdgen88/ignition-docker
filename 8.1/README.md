# Ignition 8.1.x Docker Image

If you're on Linux/macOS, you can build this image using the supplied Makefile to automate the docker image build.  There are a few build targets defined for your convenience, as outlined below.  

_NOTE: there are also build targets in the parent directory that can be used to build multiple branches (e.g. 7.9.x and 8.0.x).  They leverage the build targets mentioned here._

## Single Architecture Local Builds

To build both the _FULL_ and _EDGE_ editions locally (with a custom tag) against your native architecture:

    $ make build BASE_IMAGE_NAME=custom/ignition

This will create images `custom/ignition` with tags `8.1.x`, and `8.1` (based on the current version).

You can also specify a registry target for the `BASE_IMAGE_NAME` so you can then push those images to your custom Docker image registry:

    $ make build BASE_IMAGE_NAME=localhost:5000/custom/ignition
    $ make push-registry

... which will build and push images to the registry running at `localhost:5000`.

If you just want to build the _FULL_ image, you can specify one of the alternative build targets:

    $ make .build-full BASE_IMAGE_NAME=custom/ignition

## Multi Architecture Local Builds

There is some potential additional setup that you need to perform to get your environment setup for multi-architecture builds (consult the `.travis.yml` in the main directory for some insight), but once you're ready, it is fairly easy to conduct.  Multi-architecture builds **DO REQUIRE** a registry to push to, so keep that in mind.  The default build will target a local registry at `localhost:5000`:

    $ make multibuild

If you need to target a different registry, just override the `BASE_IMAGE_NAME` like below:

    $ make multibuild BASE_IMAGE_NAME=myregistry:5000/kcollins/ignition
