#!/usr/bin/env bash

set -euo pipefail

cd "/var/cache/downloads"

echo "Fetching latest stable kubectl version..."
KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
echo "Latest version: ${KUBECTL_VERSION}"

BASE_URL="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64"

if [[ -f "kubectl-${KUBECTL_VERSION}" && -f "kubectl-${KUBECTL_VERSION}.sha256" ]]; then
    echo "Skipping download (kubectl-${KUBECTL_VERSION} already exists)."
else
    echo "Downloading kubectl ${KUBECTL_VERSION}..."
    curl -fsSL -o "kubectl-${KUBECTL_VERSION}" "${BASE_URL}/kubectl"
    curl -fsSL -o "kubectl-${KUBECTL_VERSION}.sha256" "${BASE_URL}/kubectl.sha256"
fi

echo "Validating checksum..."
echo "$(cat "kubectl-${KUBECTL_VERSION}.sha256")  kubectl-${KUBECTL_VERSION}" | sha256sum --check --status || {
    echo "ERROR: kubectl checksum validation failed" >&2
    exit 1
}
echo "Checksum OK."

echo "Installing kubectl to /usr/bin/kubectl..."
install -o root -g root -m 0755 "kubectl-${KUBECTL_VERSION}" /usr/bin/kubectl

echo "kubectl ${KUBECTL_VERSION} installed successfully."
kubectl version --client