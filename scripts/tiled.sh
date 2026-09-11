#!/bin/bash
set -euo pipefail

compose_file="${compose_file:-$PWD/compose/docker-compose.yml}"
BEAMLINE_ACRONYM="${BEAMLINE_ACRONYM:-hex}"

docker compose -f "${compose_file}" up -d tiled caddy

# Pass the API key variable explicitly into docker compose exec
docker compose -f "${compose_file}" exec -T \
  -e TILED_SERVER_API_KEY="${TILED_SERVER_API_KEY:-secret}" \
  -e SSL_CERT_FILE="" \
  -e PYTHONHTTPSVERIFY=0 \
  tiled python -c "
import os
import urllib3
urllib3.disable_warnings()

from tiled.client import from_profile
tla = os.getenv('BEAMLINE_ACRONYM', 'xyz').lower()
TLA = tla.upper()

api_key = os.getenv(f'TILED_BLUESKY_WRITING_API_KEY_{TLA}', os.getenv('TILED_SERVER_API_KEY', 'secret'))
client = from_profile('nsls2', api_key=api_key, verify=False)

def get_or_create_container(parent, key, specs=None, metadata={}):
    try:
        return parent[key]
    except Exception:
        try:
            if specs is None:
                return parent.create_container(key, metadata=metadata)
            return parent.create_container(key, specs=specs, metadata=metadata)
        except Exception:
            return parent[key]

beamline = get_or_create_container(client, tla)

get_or_create_container(beamline, 'migration', specs=['CatalogOfBlueskyRuns'])
get_or_create_container(beamline, 'raw', specs=['CatalogOfBlueskyRuns'])

if tla == 'opls':
    client[tla]['raw'].update_metadata(metadata={'proposal_number': 123456, 'main_proposer': 'test_user'})
"