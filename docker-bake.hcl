variable "CONSUL_VERSION" {
    default = "latest"
}

target "docker-metadata-action" {}
target "github-metadata-action" {}

target "default" {
    inherits = [
        "swarmshicorp-consul",
    ]
    platforms = [
        "linux/amd64",
        "linux/arm64"
    ]
}

target "makefile" {
    inherits = [
        "swarmshicorp-consul",
    ]
    tags = [
        "swarmshicorp-consul:local"
    ]
}

target "swarmshicorp-consul" {
    context = "."
    dockerfile = "Dockerfile"
    inherits = [
        "docker-metadata-action",
        "github-metadata-action",
    ]
    args = {
        CONSUL_VERSION = "${CONSUL_VERSION}"
    }
}
