#!/bin/bash

# // SPDX-License-Identifier: LGPL-2.1-or-later
# // Copyright (c) 2015-2025 MariaDB Corporation Ab

# Script to setup MySQL with Docker registry authentication

set -e

MYSQL_VERSION="${1}"
MYSQL_DATABASE="${2}"
MYSQL_ROOT_PASSWORD="${3}"
MYSQL_PORT="${4}"
REGISTRY_USER="${5}"
REGISTRY_PASSWORD="${6}"
REGISTRY="${7}"
OS_TYPE="${8}"
WORKSPACE="${9}"
MYSQL_USER="${10}"
MYSQL_PASSWORD="${11}"

# Determine container runtime
if type podman > /dev/null 2>&1; then
    CONTAINER_RUNTIME="podman"
elif type docker > /dev/null 2>&1; then
    CONTAINER_RUNTIME="docker"
else
    echo "❌ Neither docker nor podman found"
    exit 1
fi

echo "Using container runtime: ${CONTAINER_RUNTIME}"

# Login to registry if credentials provided
if [[ -n "${REGISTRY_USER}" && -n "${REGISTRY_PASSWORD}" ]]; then
    CONTAINER_LOGIN_ARGS=()
    CONTAINER_LOGIN_ARGS+=("--username" "${REGISTRY_USER}")
    CONTAINER_LOGIN_ARGS+=("--password" "${REGISTRY_PASSWORD}")
    CMD="${CONTAINER_RUNTIME} login ${REGISTRY} ${CONTAINER_LOGIN_ARGS[@]}"
    echo "Logging into ${REGISTRY}..."
    eval "${CMD}"
    exit_code=$?
    if [[ "${exit_code}" == "0" ]]; then
        echo "✅ Connected to ${REGISTRY}"
    else
        echo "⚠️ Failed to connect to ${REGISTRY}"
        exit 1
    fi
else
    if [[ -n "${REGISTRY}" && "${REGISTRY}" != "docker.io" ]]; then
        echo "❌ Registry user and/or password was not set for ${REGISTRY}"
        exit 1
    fi
fi

# Determine image name
if [[ -n "${REGISTRY}" && "${REGISTRY}" != "docker.io" ]]; then
    IMAGE="${REGISTRY}:${MYSQL_VERSION}"
else
    IMAGE="mysql:${MYSQL_VERSION}"
fi

echo "Using MySQL image: ${IMAGE}"

# Prepare SSL certificate paths
if [[ "${OS_TYPE}" == windows* ]]; then
    # Windows paths
    SSL_CA="${WORKSPACE}/.github/workflows/certs/ca.crt"
    SSL_CERT="${WORKSPACE}/.github/workflows/certs/server.crt"
    SSL_KEY="${WORKSPACE}/.github/workflows/certs/server.key"
    CERT_MOUNT="${WORKSPACE}/.github/workflows/certs:/etc/mysql/certs"
else
    # Unix paths
    SSL_CA="/etc/mysql/certs/ca.crt"
    SSL_CERT="/etc/mysql/certs/server.crt"
    SSL_KEY="/etc/mysql/certs/server.key"
    CERT_MOUNT="${WORKSPACE}/.github/workflows/certs:/etc/mysql/certs"
fi

# Fix cert permissions for MySQL (strict about SSL file ownership)
chmod 644 "${WORKSPACE}/.github/workflows/certs/ca.crt" \
           "${WORKSPACE}/.github/workflows/certs/server.crt" || true
chmod 640 "${WORKSPACE}/.github/workflows/certs/server.key" || true

# Run MySQL container
echo "Starting MySQL container..."
${CONTAINER_RUNTIME} run -d \
    --name mysql-test \
    -e MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}" \
    -e MYSQL_DATABASE="${MYSQL_DATABASE}" \
    $( [[ -n "${MYSQL_USER}" ]] && echo "-e MYSQL_USER=${MYSQL_USER}" ) \
    $( [[ -n "${MYSQL_PASSWORD}" ]] && echo "-e MYSQL_PASSWORD=${MYSQL_PASSWORD}" ) \
    -p ${MYSQL_PORT}:3306 \
    -v "${CERT_MOUNT}:ro" \
    ${IMAGE} \
    --ssl-ca=/etc/mysql/certs/ca.crt \
    --ssl-cert=/etc/mysql/certs/server.crt \
    --ssl-key=/etc/mysql/certs/server.key \
    --max-connections=500 \
    --character-set-server=utf8mb4 \
    --collation-server=utf8mb4_general_ci

echo "Waiting for MySQL to be ready..."
for i in {1..40}; do
    if ${CONTAINER_RUNTIME} exec mysql-test mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" > /dev/null 2>&1; then
        echo "✅ MySQL is ready"
        exit 0
    fi
    echo "Waiting... ($i/40)"
    sleep 2
done

echo "❌ MySQL failed to start within timeout"
${CONTAINER_RUNTIME} logs mysql-test
exit 1
