# docker-bake.hcl
group "default" {
    targets = [
        "7_9",
        "8_1"
    ]
}

variable "BASE_IMAGE_NAME" {
    default = "localhost:5000/kcollins/ignition"
}

variable "IGNITION_VERSION_79" {
    default = "7.9.21"
}

variable "IGNITION_VERSION_81" {
    default = "8.1.43"
}

# Ignition Base Build Targets
target "7_9-base" {
    context = "7.9"
    contexts = {
        jre-base = "docker-image://eclipse-temurin:8-jre-jammy"
    }
    platforms = [
        "linux/amd64",
        "linux/arm",
    ]
}

target "8_1-base" {
    context = "8.1"
    contexts = {
        ubuntu-base = "docker-image://ubuntu:24.04"
    }
    platforms = [
        "linux/amd64", 
        "linux/arm64", 
        "linux/arm",
    ]
}

# Ignition 7.9 Build Targets
group "7_9" {
    targets = [
        "7_9-full",
        "7_9-edge"
    ]
}

target "7_9-full" {
    inherits = ["7_9-base"]
    args = {
        BUILD_EDITION = "FULL"
    }
    cache-to = ["type=registry,ref=${BASE_IMAGE_NAME}:cache-${IGNITION_VERSION_79}"]
    cache-from = ["type=registry,ref=${BASE_IMAGE_NAME}:cache-${IGNITION_VERSION_79}"]
    tags = [
        "${BASE_IMAGE_NAME}:${IGNITION_VERSION_79}",
        "${BASE_IMAGE_NAME}:7.9",
    ]
}

target "7_9-edge" {
    inherits = ["7_9-base"]
    args = {
        BUILD_EDITION = "EDGE"
    }
    cache-to = ["type=registry,ref=${BASE_IMAGE_NAME}:cache-${IGNITION_VERSION_79}-edge"]
    cache-from = ["type=registry,ref=${BASE_IMAGE_NAME}:cache-${IGNITION_VERSION_79}-edge"]
    tags = [
        "${BASE_IMAGE_NAME}:${IGNITION_VERSION_79}-edge",
        "${BASE_IMAGE_NAME}:7.9-edge",
    ]
}

# Ignition 8.1 Build Targets
group "8_1" {
    targets = [
        "8_1-full",
        "8_1-slim"
    ]
}

target "8_1-full" {
    inherits = ["8_1-base"]
    args = {
        BUILD_EDITION = "STABLE"
    }
    cache-to = ["type=registry,ref=${BASE_IMAGE_NAME}:cache-${IGNITION_VERSION_81}"]
    cache-from = ["type=registry,ref=${BASE_IMAGE_NAME}:cache-${IGNITION_VERSION_81}"]
    tags = [
        "${BASE_IMAGE_NAME}:${IGNITION_VERSION_81}",
        "${BASE_IMAGE_NAME}:8.1",
        "${BASE_IMAGE_NAME}:latest"
    ]
}

target "8_1-slim" {
    inherits = ["8_1-base"]
    args = {
        ZIP_EXCLUSION_RESOURCE_LIST = "designerlauncher,perspectiveworkstation,visionclientlauncher"
        ZIP_EXCLUSION_ARCHITECTURE_LIST = "mac,linux64,win64"
    }
    cache-to = ["type=registry,ref=${BASE_IMAGE_NAME}:cache-${IGNITION_VERSION_81}-slim"]
    cache-from = ["type=registry,ref=${BASE_IMAGE_NAME}:cache-${IGNITION_VERSION_81}-slim"]
    tags = [
        "${BASE_IMAGE_NAME}:${IGNITION_VERSION_81}-slim",
        "${BASE_IMAGE_NAME}:8.1-slim",
        "${BASE_IMAGE_NAME}:latest-slim"
    ]
}

target "nightly" {
    inherits = ["8_1-full"]
    args = {
        BUILD_EDITION = "nightly"
    }
    no-cache = true
    tags = [
        "${BASE_IMAGE_NAME}:nightly"
    ]
}

target "nightly-slim" {
    inherits = ["8_1-slim"]
    args = {
        BUILD_EDITION = "nightly"
    }
    no-cache = true
    tags = [
        "${BASE_IMAGE_NAME}:nightly"
    ]
}
