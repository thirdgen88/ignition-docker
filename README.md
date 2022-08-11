# Ignition on Docker - Community Image

[![8.1 Build Status](https://github.com/thirdgen88/ignition-docker/actions/workflows/multibuild-8.1.yml/badge.svg)](https://github.com/thirdgen88/ignition-docker/actions)
[![Gitter](https://img.shields.io/gitter/room/nwjs/nw.js.svg)](https://gitter.im/ignition-docker/Lobby?utm_source=share-link&utm_medium=link&utm_campaign=share-link)
[![Docker Stars](https://img.shields.io/docker/stars/kcollins/ignition.svg)](https://hub.docker.com/r/kcollins/ignition)
[![Docker Pulls](https://img.shields.io/docker/pulls/kcollins/ignition.svg)](https://hub.docker.com/r/kcollins/ignition)
<br/>
![Ignition 8.1.19](https://img.shields.io/badge/ignition-8.1.19-brightgreen.svg?logo=data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAEt2lUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4KPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iWE1QIENvcmUgNS41LjAiPgogPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4KICA8cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0iIgogICAgeG1sbnM6dGlmZj0iaHR0cDovL25zLmFkb2JlLmNvbS90aWZmLzEuMC8iCiAgICB4bWxuczpleGlmPSJodHRwOi8vbnMuYWRvYmUuY29tL2V4aWYvMS4wLyIKICAgIHhtbG5zOnBob3Rvc2hvcD0iaHR0cDovL25zLmFkb2JlLmNvbS9waG90b3Nob3AvMS4wLyIKICAgIHhtbG5zOnhtcD0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wLyIKICAgIHhtbG5zOnhtcE1NPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvbW0vIgogICAgeG1sbnM6c3RFdnQ9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9zVHlwZS9SZXNvdXJjZUV2ZW50IyIKICAgdGlmZjpJbWFnZUxlbmd0aD0iNDgiCiAgIHRpZmY6SW1hZ2VXaWR0aD0iNDgiCiAgIHRpZmY6UmVzb2x1dGlvblVuaXQ9IjIiCiAgIHRpZmY6WFJlc29sdXRpb249IjcyLjAiCiAgIHRpZmY6WVJlc29sdXRpb249IjcyLjAiCiAgIGV4aWY6UGl4ZWxYRGltZW5zaW9uPSI0OCIKICAgZXhpZjpQaXhlbFlEaW1lbnNpb249IjQ4IgogICBleGlmOkNvbG9yU3BhY2U9IjEiCiAgIHBob3Rvc2hvcDpDb2xvck1vZGU9IjMiCiAgIHBob3Rvc2hvcDpJQ0NQcm9maWxlPSJzUkdCIElFQzYxOTY2LTIuMSIKICAgeG1wOk1vZGlmeURhdGU9IjIwMjAtMTEt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)
![Ignition 7.9.21](https://img.shields.io/badge/ignition-7.9.21-green.svg)

This is the Git repository for the Ignition Docker Development image.  It includes a `docker-bake.hcl` in addition to the `Dockerfile` entries to allow for easy image building.  See the [Docker Hub page][1] for the full README on how to utilize this Docker image and for information regarding contributing and registering issues.

The full README documentation from the Docker Hub page is maintained in the [docs](https://github.com/thirdgen88/ignition-docker/tree/main/docs) folder in the event that you find typos or areas that need more detail or content.

## Building the Image

When updated, this image is pushed to [Docker Hub][1] via GH actions.  To customize and build your own version of the image, use the instructions in this section.

### Available Build Targets

The image build leverages [docker buildx bake][2] to provide targets for each of the available permutations of the image.

Target     | Description
---------- | -----------
`8_1-full` | Latest 8.1.x image (Standard, Edge, Maker Editions)
`8_1-slim` | Same as `8_1-full` but without Launchers and Perspective Workstation
`8_1`      | Group of `8_1-full` and `8_1-slim` targets
`7_9-full` | Latest 7.9.x image (Standard Edition)
`7_9-edge` | Latest 7.9.x image (Edge Edition)

By default, the `BASE_IMAGE_NAME` variable refers to `localhost:5000/kcollins/ignition`.  You can override the base image name by setting this environment variable prior to running the various `docker buildx bake` commands in the next sections.

### Single Architecture Local Builds

If you want to build an image for your local Docker installation (without a registry), you can build a target with the following:

    docker buildx bake --load --set \*.platform=linux/arm64 8_1-full

Note that you must specify a platform in this mode (`linux/amd64`, `linux/arm64`, or `linux/arm`) since manifests are not supported with exporting directly to Docker Engine.

### Multi Architecture Builds

If you want to build a multi-platform image+manifest, you must have a registry to target.  You can build a target with the following:

    docker buildx bake --push 8_1-full

[1]: https://hub.docker.com/r/kcollins/ignition/
[2]: https://docs.docker.com/engine/reference/commandline/buildx_bake/
