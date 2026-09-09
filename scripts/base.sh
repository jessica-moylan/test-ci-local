# get the repo with a specific branch from a specific path and copy it to the /workspace directory in the base docker container
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"
compose_file="${root}/compose/docker-compose.yml"
post_data_security_file="${root}/configs/post_data_security.txt"

ENDSTATION="${1:-hex}"
BEAMLINE_REPO="${2:-hex-profile-collection}"
echo "Using endstation: ${ENDSTATION}"
echo "Using beamline repo: ${BEAMLINE_REPO}"
BEAMLINE_BRANCH="${3:-main}"

# Variables ----------------------------------------------------------------------------------------------------------------------------------------------
TILED_SERVER_API_KEY_VAR="TILED_BLUESKY_WRITING_API_KEY_${ENDSTATION^^}"
TILED_SERVER_API_KEY="${!TILED_SERVER_API_KEY_VAR:-secret}"

# Start the base docker container that will be where all of the configuration files and scripts will live ------------------------------------------------
docker compose -f "${compose_file}" up -d base

# Grab the profile and clone it to a temporary directory so than it can be copied to docker
TMP_REPO="${root}/.beamline-repos/${BEAMLINE_REPO}"
mkdir -p "${TMP_REPO}"
if [ ! -d "${TMP_REPO}/.git" ]; then
    git clone --branch "${BEAMLINE_BRANCH}" --single-branch "https://github.com/NSLS2/${BEAMLINE_REPO}.git" "${TMP_REPO}"
    docker cp "${TMP_REPO}" hexsim-base:/workspace/${BEAMLINE_REPO}
    rm -rf "${TMP_REPO}"
fi

# Verify pixi is available in the base container.
docker exec -i hexsim-base sh -lc 'command -v pixi >/dev/null'

# Build important tiled configuration files and copy them to the base docker container ---------------------------------------------------------------------
tiled_profiles_dir="/app/.config/tiled/profiles"

docker exec -it hexsim-base mkdir -p "$tiled_profiles_dir"

# Builds the profile.yml
LOCAL_TILED_URI="http://127.0.0.1:8000/api/v1/metadata/${ENDSTATION}/raw"

if [ -f "$post_data_security_file" ] && grep -qw "$ENDSTATION" "$post_data_security_file"; then
        echo "Beamline ${ENDSTATION} is in post_data_security.txt, creating a direct profile for Tiled"
    cat <<EOF | docker exec -i hexsim-base sh -lc "cat > '$tiled_profiles_dir/profiles.yml'"
${ENDSTATION}:
    direct:
        authentication:
            allow_anonymous_access: true
        trees:
            - tree: databroker.mongo_normalized:Tree.from_uri
                path: /
                args:
                    uri: mongodb://localhost:27017/metadatastore-local
                    asset_registry_uri: mongodb://localhost:27017/asset-registry-local
EOF
else
    cat <<EOF | docker exec -i hexsim-base sh -lc "cat > '$tiled_profiles_dir/profiles.yml'"
${ENDSTATION}:
    uri: ${LOCAL_TILED_URI}
EOF
fi

# Builds the nsls2.yml
cat <<EOF | docker exec -i hexsim-base sh -lc "cat > '$tiled_profiles_dir/nsls2.yml'"
nsls2:
    uri: https://tiled.nsls2.bnl.gov
    headers:
        Authorization: "Apikey ${TILED_SERVER_API_KEY}"
EOF

# Finish tiled setup
echo "[base] Tiled config files created, now set up tiled"
export compose_file="${root}/compose/docker-compose.yml"
export BEAMLINE_ACRONYM="${ENDSTATION}"

"$here/tiled.sh"


# Builds and creates Redis files ----------------------------------------------------------------------------------------------------------------------


# Runs bsui.py interactively within the base docker container ----------------------------------------------------------------------------------------------------------------
docker exec -it hexsim-base bash -lc "
cd /workspace/${BEAMLINE_REPO}
export BEAMLINE_ACRONYM=${ENDSTATION}
export ENDSTATION_ACRONYM=${ENDSTATION}
export TILED_BLUESKY_WRITING_API_KEY_${ENDSTATION^^}=secret
export TILED_BLUESKY_WRITING_API_KEY=secret
export TILED_SERVER_API_KEY=secret
pixi run -e terminal ipython --profile=test --pdb -i /workspace/scripts/bsui.py
"


# Extract important variables and save that to a file that will be in the directory, ex (endstation, redis-host)
# in the same file set variables: This will be used throughout the run
    # api keys
    # redis host
    # mongo host
    # kafka host
    # tiled host
    # passwords & users

# make any paths/files that are possible right now that are not already made and provide it to the base docker container

# Start docker containers for the rest

