set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"
compose_file="${root}/compose/docker-compose.yml"
post_data_security_file="${root}/configs/post_data_security.txt"
certdir="$root/compose/certs"

ENDSTATION="${1:-hex}"
BEAMLINE_REPO="${2:-hex-profile-collection}"
echo "Using endstation: ${ENDSTATION}"
echo "Using beamline repo: ${BEAMLINE_REPO}"
BEAMLINE_BRANCH="${3:-main}"
REDIS_HOST=$4

# Variables ----------------------------------------------------------------------------------------------------
TILED_SERVER_API_KEY_VAR="TILED_BLUESKY_WRITING_API_KEY_${ENDSTATION^^}"
TILED_SERVER_API_KEY="${!TILED_SERVER_API_KEY_VAR:-secret}"

# Generate Certificates -------------------------------------------------------------
mkdir -p "$certdir"

if [ ! -f "$certdir/redis.crt" ]; then
    echo "[hexsim] generating new Redis TLS certificate..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$certdir/redis.key" \
        -out "$certdir/redis.crt" \
        -subj "/CN=${REDIS_HOST}" \
        -addext "subjectAltName=DNS:${REDIS_HOST},DNS:localhost,DNS:hexsim-redis,IP:127.0.0.1"
    chmod 644 "$certdir/redis.key" "$certdir/redis.crt"
fi

if [ ! -f "$certdir/tiled.crt" ]; then
    echo "[hexsim] generating new tiled TLS certificate..."
    openssl req -x509 -newkey rsa:2048 -sha256 -days 1 -nodes \
        -keyout "$certdir/tiled.key" \
        -out "$certdir/tiled.crt" \
        -subj "/CN=tiled.nsls2.bnl.gov" \
        -addext "subjectAltName=DNS:tiled.nsls2.bnl.gov,DNS:api.nsls2.bnl.gov,IP:127.0.0.1"
    chmod 644 "$certdir/tiled.key" "$certdir/tiled.crt"
fi

# 2. START CONTAINERS (Now they boot with valid certs in place) ------------------------------------------------
docker compose -f "${compose_file}" up -d --wait base redis

docker exec hexsim-base sh -lc ': > /etc/bluesky/redis.secret'

cat "${root}/configs/kafka.yml" | docker exec -i hexsim-base sh -lc "cat > /etc/bluesky/kafka.yml"

docker cp "${root}/configs/pyOlog.conf" "hexsim-base:/root/.pyOlog.conf"

# Force refresh CA certs inside base to ensure redis.crt is loaded into system trust
docker exec hexsim-base update-ca-certificates --fresh

# Grab the profile and clone it to a temporary directory so than it can be copied to docker -------------------
TMP_REPO="${root}/.beamline-repos/${BEAMLINE_REPO}"
mkdir -p "${root}/.beamline-repos"

# Clone the beamline repo if it doesn't exist locally, otherwise update it
if [ ! -d "${TMP_REPO}/.git" ]; then
    echo "Cloning ${BEAMLINE_REPO} (${BEAMLINE_BRANCH})..."
    git clone --branch "${BEAMLINE_BRANCH}" --single-branch "https://github.com/NSLS2/${BEAMLINE_REPO}.git" "${TMP_REPO}"
else
    echo "Updating existing local repo ${BEAMLINE_REPO}..."
    git -C "${TMP_REPO}" fetch origin
    git -C "${TMP_REPO}" checkout "${BEAMLINE_BRANCH}"
    git -C "${TMP_REPO}" pull origin "${BEAMLINE_BRANCH}"
fi

# Sync local repo content into the hexsim-base (this will overwrite any existing content in the container's workspace)
# This will be relvant if you make local changes to the beamline repo and want to test
echo "Syncing ${BEAMLINE_REPO} to container workspace..."
docker exec hexsim-base rm -rf "/workspace/${BEAMLINE_REPO}"
docker exec hexsim-base mkdir -p "/workspace/${BEAMLINE_REPO}"
docker cp "${TMP_REPO}/." "hexsim-base:/workspace/${BEAMLINE_REPO}/"

# 4. Create more configuration for Tiled ---------------------------------------------------------------------
tiled_profiles_dir="/etc/tiled/profiles"
docker exec -it hexsim-base mkdir -p "$tiled_profiles_dir"

LOCAL_TILED_URI="https://tiled.nsls2.bnl.gov/api/v1/metadata/${ENDSTATION}/raw"

# Builds the profile.yml
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

# Finish Tiled Setup -------------------------------------------------------------------------------------------
export compose_file="${root}/compose/docker-compose.yml"
export BEAMLINE_ACRONYM="${ENDSTATION}"
export BEAMLINE_REPO="${BEAMLINE_REPO}"
"$here/tiled.sh"

# Runs bsui.py interactively within the base docker container ---------------------------------------------------
docker exec -it hexsim-base bash -lc "
cd /workspace/${BEAMLINE_REPO}
export BEAMLINE_ACRONYM=${ENDSTATION}
export ENDSTATION_ACRONYM=${ENDSTATION}
export TILED_BLUESKY_WRITING_API_KEY_${ENDSTATION^^}=secret
export TILED_BLUESKY_WRITING_API_KEY=secret
export TILED_SERVER_API_KEY=${TILED_SERVER_API_KEY}
export TILED_API_KEY=${TILED_SERVER_API_KEY}
pixi run -e terminal ipython --profile=test --pdb -i /workspace/scripts/bsui.py
"
#export PYTHON_KEYRING_BACKEND=keyring.backends.null.Keyring
