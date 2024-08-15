#!/usr/bin/env sh

# ================================================
# Enrise development proxy
# find out more: https://enri.se/development-proxy
# ================================================

if ($(docker ps | grep -q development-proxy)); then
    echo "Development hosts proxy is already running."
    exit 0
fi

get_config() {
    if [ -f "$DEVELOPMENT_PROXY_CONFIG_FILE" ]; then
        docker run --rm -i -v "$DEVELOPMENT_PROXY_CONFIG_HOME":/workdir mikefarah/yq "$1" proxy-config.yml
    fi
}

development_proxy_name="development-proxy"
DEVELOPMENT_PROXY_CONFIG_HOME="${DEVELOPMENT_PROXY_CONFIG_HOME:-$HOME/.development-proxy}"
DEVELOPMENT_PROXY_CONFIG_FILE="${DEVELOPMENT_PROXY_CONFIG_FILE:-$DEVELOPMENT_PROXY_CONFIG_HOME/proxy-config.yml}"

mkdir -p $DEVELOPMENT_PROXY_CONFIG_HOME/config || true
mkdir -p $DEVELOPMENT_PROXY_CONFIG_HOME/certs || true

TRAEFIK_VERSION=${TRAEFIK_VERSION:-$(get_config ".traefik_version")}
TRAEFIK_VERSION=${TRAEFIK_VERSION:-"v2.10"}

TRAEFIK_DASH_PORT=${TRAEFIK_DASH_PORT:-$(get_config ".dashboard_port")}
TRAEFIK_DASH_PORT="${TRAEFIK_DASH_PORT:-"10081"}"

IFS='' read -d '' -r default_entrypoints <<EOF
  --entrypoints.web.address=:80
  --entrypoints.web-secure.address=:443
  --entrypoints.traefik.address=:$TRAEFIK_DASH_PORT
EOF
IFS='' read -d '' -r default_exposed_ports <<EOF
  --publish 80:80
  --publish 443:443
  --publish $TRAEFIK_DASH_PORT:$TRAEFIK_DASH_PORT
EOF
TREAFIK_ENTRYPOINTS="${TREAFIK_ENTRYPOINTS:-$default_entrypoints}"
TRAEFIK_DOCKER_EXPOSED_PORTS="${TRAEFIK_DOCKER_EXPOSED_PORTS:-$default_exposed_ports}"

entrypoints=$(get_config ".entrypoints" | tr -d ' ')
for entrypoint in ${entrypoints}
do
    name=$(echo "$entrypoint" | sed 's/:/ /g' | cut -f1 -d' ')
    port=$(echo "$entrypoint" | sed 's/:/ /g' | cut -f2 -d' ')
    TREAFIK_ENTRYPOINTS="$TREAFIK_ENTRYPOINTS --entrypoints.${name}.address=:${port}"
    TRAEFIK_DOCKER_EXPOSED_PORTS="$TRAEFIK_DOCKER_EXPOSED_PORTS --publish ${port}:${port}"
done

echo "Starting development proxy..."
docker network create development-proxy > /dev/null 2>&1 || true
(docker run \
    --detach \
    --rm \
    $TRAEFIK_DOCKER_EXPOSED_PORTS \
    --volume /var/run/docker.sock:/var/run/docker.sock:ro \
    --volume $DEVELOPMENT_PROXY_CONFIG_HOME/config:/var/config:ro \
    --volume $DEVELOPMENT_PROXY_CONFIG_HOME/certs:/var/certs:ro \
    --name $development_proxy_name \
    --network $development_proxy_name \
    traefik:$TRAEFIK_VERSION \
    --api.insecure=true \
    --providers.docker=true \
    --providers.docker.exposedbydefault=false \
    --providers.file.directory=/var/config \
    --providers.file.watch=true \
    $TREAFIK_ENTRYPOINTS > /dev/null  && echo "Started.")
