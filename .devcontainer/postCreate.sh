#!/bin/bash
set -euxo pipefail

# Clone the Skosmos source
if [ ! -d "skosmos-src" ]; then
  git clone --depth 1 https://github.com/NatLibFi/Skosmos.git skosmos-src
# If we rebuild the dev container, undo the changes we made to the config
else
  git -C skosmos-src restore -- dockerfiles/config/config-docker-compose.ttl
  rm -f skosmos-src/dockerfiles/config/config-docker-compose.ttl.bak
  echo ''
fi

# Delete default vocabulary blocks
sed -i.bak -e '/^:unesco /,/^ *\.$/d' -e '/^:stw /,/^ *\.$/d' skosmos-src/dockerfiles/config/config-docker-compose.ttl

# Append the vocabulary block info
cat <<'EOF' >> skosmos-src/dockerfiles/config/config-docker-compose.ttl
:MAIA a skosmos:Vocabulary, void:Dataset ;
  dc:title "MAIA"@en ;
  skosmos:shortName "MAIA" ;
  skosmos:defaultLanguage "en" ;
  void:uriSpace "http://connectivity-hub.com/terms/" ;
  skosmos:sparqlEndpoint <http://fuseki:3030/skosmos/sparql> ;
  skosmos:sparqlGraph <http://example.org/graph/dev> ;
  skosmos:showTopConcepts true ;
  skosmos:fullAlphabeticalIndex true .
EOF

# Sometimes Docker is not ready when we want to use it, so we want to make sure it is ready
ensure_docker() {
  if ! docker info >/dev/null 2>&1; then
    echo "[INFO] Starting Docker daemon…"
    sudo /usr/local/share/docker-init.sh || true
  fi
  for i in {1..90}; do
    if docker info >/dev/null 2>&1; then
      echo "[INFO] Docker is ready."
      return 0
    fi
    echo "[INFO] Waiting for Docker…"
    sleep 1
  done
  echo "[ERROR] Docker daemon did not become ready."
  ps -ef | grep -E '[d]ockerd' || true
  sudo tail -n 200 /var/log/dockerd.log 2>/dev/null || true
  exit 1
}

# Wait for Docker
ensure_docker

# Retry Docker-compose three times in case the daemon flaps
for a in 1 2 3; do
  if docker compose -f skosmos-src/docker-compose.yml up -d --build; then
    break
  fi
  echo "[WARN] docker compose failed (attempt $a), retrying in 3s…"
  sleep 3
  ensure_docker
done

# Wait until SPARQL endpoint is ready
for i in {1..60}; do
  if curl -sS -G 'http://localhost:9030/skosmos/sparql' --data-urlencode 'query=ASK{}' -H 'Accept: text/boolean' -o /dev/null; then break; fi
  sleep 1
done

# Load TTL into the graph
curl --retry 6 --retry-delay 2 --retry-connrefused -sSf -X PUT -H "Content-Type: text/turtle;charset=utf-8" --data-binary @concepts.ttl "http://localhost:9030/skosmos/data?graph=http://example.org/graph/dev"

