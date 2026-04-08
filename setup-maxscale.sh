#!/bin/bash

# Setup MaxScale with Docker/Podman
# This script sets up MaxScale to proxy connections to MariaDB Enterprise

set -e

MAXSCALE_TAG="$1"
REGISTRY_USER="$2"
REGISTRY_PASSWORD="$3"
DB_ROOT_PASSWORD="$4"
WORKSPACE="$5"

MXS_PORT="${TEST_MXS_PORT:-3306}"
MXS_SSL_PORT="${TEST_MAXSCALE_TLS_PORT:-4009}"
MXS_REST_PORT="8989"
DB_PORT="3305"  # MariaDB runs on 3305 when MaxScale is enabled

echo "🔧 Setting up MaxScale ${MAXSCALE_TAG}..."

# Determine container runtime
if type podman > /dev/null 2>&1; then
    CONTAINER_RUNTIME="podman"
elif type docker > /dev/null 2>&1; then
    CONTAINER_RUNTIME="docker"
else
    echo "❌ No container runtime (docker/podman) available"
    exit 1
fi

echo "✅ Using container runtime: ${CONTAINER_RUNTIME}"

# Login to MariaDB Enterprise registry
if [[ -n "${REGISTRY_USER}" && -n "${REGISTRY_PASSWORD}" ]]; then
    echo "🔐 Logging in to docker.mariadb.com..."
    echo "${REGISTRY_PASSWORD}" | ${CONTAINER_RUNTIME} login docker.mariadb.com --username "${REGISTRY_USER}" --password-stdin
    if [ $? -eq 0 ]; then
        echo "✅ Successfully logged in to docker.mariadb.com"
    else
        echo "❌ Failed to login to docker.mariadb.com"
        exit 1
    fi
else
    echo "❌ Registry credentials not provided"
    exit 1
fi

# Create MaxScale configuration directory
MAXSCALE_CONF_DIR="${WORKSPACE}/.github/workflows/maxscale-conf"
mkdir -p "${MAXSCALE_CONF_DIR}"

# Create MaxScale configuration file
cat > "${MAXSCALE_CONF_DIR}/maxscale.cnf" << EOF
[maxscale]
threads=auto
admin_host=0.0.0.0
admin_port=${MXS_REST_PORT}
admin_secure_gui=false

# Monitor for the MariaDB server
[MariaDB-Monitor]
type=monitor
module=mariadbmon
servers=server1
user=maxscale
password=${DB_ROOT_PASSWORD}
monitor_interval=2000ms

# ReadWrite Split Router Service
[Read-Write-Service]
type=service
router=readwritesplit
servers=server1
user=maxscale
password=${DB_ROOT_PASSWORD}

# ReadWrite Split Listener (non-SSL)
[Read-Write-Listener]
type=listener
service=Read-Write-Service
protocol=MariaDBClient
port=${MXS_PORT}

# ReadWrite Split Listener (SSL)
[Read-Write-SSL-Listener]
type=listener
service=Read-Write-Service
protocol=MariaDBClient
port=${MXS_SSL_PORT}
ssl=true
ssl_cert=/etc/maxscale.d/certs/server.crt
ssl_key=/etc/maxscale.d/certs/server.key
ssl_ca=/etc/maxscale.d/certs/ca.crt
ssl_verify_peer_certificate=false

# MariaDB Server
[server1]
type=server
address=mariadb.example.com
port=${DB_PORT}
protocol=MariaDBBackend
ssl=true
ssl_ca=/etc/maxscale.d/certs/ca.crt
ssl_verify_peer_certificate=true
EOF

echo "✅ MaxScale configuration created at ${MAXSCALE_CONF_DIR}/maxscale.cnf"

# Create MaxScale user in MariaDB before starting MaxScale
echo "👤 Creating MaxScale user in MariaDB..."
${CONTAINER_RUNTIME} exec mariadbcontainer mariadb -uroot -p"${DB_ROOT_PASSWORD}" -e "
    CREATE USER IF NOT EXISTS 'maxscale'@'%' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
    GRANT ALL PRIVILEGES ON *.* TO 'maxscale'@'%' WITH GRANT OPTION;
    FLUSH PRIVILEGES;
"

if [ $? -eq 0 ]; then
    echo "✅ MaxScale user created successfully"
else
    echo "❌ Failed to create MaxScale user"
    exit 1
fi

# Pull MaxScale image
MAXSCALE_IMAGE="docker.mariadb.com/maxscale:${MAXSCALE_TAG}"
echo "📥 Pulling MaxScale image: ${MAXSCALE_IMAGE}"
${CONTAINER_RUNTIME} pull "${MAXSCALE_IMAGE}"

# Run MaxScale container
echo "🚀 Starting MaxScale container..."
${CONTAINER_RUNTIME} run -d \
    --name maxscalecontainer \
    --network host \
    -v "${MAXSCALE_CONF_DIR}/maxscale.cnf:/etc/maxscale.cnf" \
    -v "${WORKSPACE}/.github/workflows/certs:/etc/maxscale.d/certs:ro" \
    "${MAXSCALE_IMAGE}"

if [ $? -eq 0 ]; then
    echo "✅ MaxScale container started successfully"
else
    echo "❌ Failed to start MaxScale container"
    exit 1
fi

# Wait for MaxScale to be ready
echo "⏳ Waiting for MaxScale to be ready..."
MAX_WAIT=30
WAIT_COUNT=0

while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    if ${CONTAINER_RUNTIME} exec maxscalecontainer maxctrl --hosts 127.0.0.1:${MXS_REST_PORT} show maxscale > /dev/null 2>&1; then
        echo "✅ MaxScale is ready!"
        break
    fi
    sleep 1
    WAIT_COUNT=$((WAIT_COUNT + 1))
    echo "⏳ Waiting... (${WAIT_COUNT}s/${MAX_WAIT}s)"
done

if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
    echo "❌ MaxScale failed to become ready within ${MAX_WAIT} seconds"
    echo "📋 MaxScale logs:"
    ${CONTAINER_RUNTIME} logs maxscalecontainer
    exit 1
fi

# Display MaxScale status
echo "📊 MaxScale status:"
${CONTAINER_RUNTIME} exec maxscalecontainer maxctrl --hosts 127.0.0.1:${MXS_REST_PORT} list servers
${CONTAINER_RUNTIME} exec maxscalecontainer maxctrl --hosts 127.0.0.1:${MXS_REST_PORT} list services

echo ""
echo "✅ MaxScale setup complete!"
echo "   MaxScale Port (non-SSL): ${MXS_PORT}"
echo "   MaxScale Port (SSL): ${MXS_SSL_PORT}"
echo "   MaxScale REST API: ${MXS_REST_PORT}"
echo ""
echo "Environment variables set:"
echo "   TEST_MXS_PORT=${MXS_PORT}"
echo "   TEST_MAXSCALE_TLS_PORT=${MXS_SSL_PORT}"
