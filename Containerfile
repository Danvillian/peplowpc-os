# PeplowPC OS
# A Fedora Atomic (Silverblue) image with PeplowPC security, privacy and branding layered on top.
# Built by .github/workflows/build.yml, published to GHCR, signed with cosign.

ARG FEDORA_VERSION=45
ARG BASE_IMAGE=quay.io/fedora-ostree-desktops/silverblue

# Build context stage: nothing here ends up in the final image except what build.sh copies.
FROM scratch AS ctx
COPY build_files /build_files
COPY system_files /system_files
# keys/ holds cosign.pub (public signing key). It may be empty for local test builds.
COPY keys /keys

FROM ${BASE_IMAGE}:${FEDORA_VERSION}

ARG FEDORA_VERSION
ARG IMAGE_NAME=peplowpc-os
ARG IMAGE_REGISTRY=ghcr.io/danvillian
ARG IMAGE_TAG=stable
ARG IMAGE_VERSION=dev

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    FEDORA_VERSION="${FEDORA_VERSION}" \
    IMAGE_NAME="${IMAGE_NAME}" \
    IMAGE_REGISTRY="${IMAGE_REGISTRY}" \
    IMAGE_TAG="${IMAGE_TAG}" \
    IMAGE_VERSION="${IMAGE_VERSION}" \
    bash /ctx/build_files/build.sh

LABEL org.opencontainers.image.title="PeplowPC OS" \
      org.opencontainers.image.description="Security and privacy first desktop, in plain English. Based on Fedora Silverblue." \
      org.opencontainers.image.url="https://peplowpc.com/" \
      org.opencontainers.image.vendor="PeplowPC" \
      containers.bootc=1

# Fails the build if the image breaks bootc rules (for example, content in /var it should not have).
RUN bootc container lint
