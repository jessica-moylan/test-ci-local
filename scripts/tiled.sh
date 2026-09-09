#!/bin/bash
set -euo pipefail

compose_file="${compose_file:-$PWD/compose/docker-compose.yml}"
BEAMLINE_ACRONYM="${BEAMLINE_ACRONYM:-hex}"

docker compose -f "${compose_file}" up -d tiled

docker compose -f "${compose_file}" exec -T tiled python -c "
import os
from tiled.client import from_profile
tla = os.getenv('BEAMLINE_ACRONYM', 'xyz').lower()
TLA = tla.upper()
client = from_profile('nsls2', api_key=os.getenv(f'TILED_BLUESKY_WRITING_API_KEY_{TLA}', 'secret'))

def get_or_create_container(parent, key, specs=None, metadata = {}):
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