set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"
compose_file="${root}/compose/docker-compose.yml"
post_data_security_file="${root}/configs/post_data_security.txt"
certdir="$root/compose/certs"

ENDSTATION="${1:-hex}"

if [[ ${ENDSTATION} == "xfm-maia" ]]; then
    ENDSTATION="xfm"
fi
export ENDSTATION
BEAMLINE_REPO="${2:-hex-profile-collection}"
BEAMLINE_BRANCH="${3:-main}"

declare -A redis_host

redis_host[six]="xf02id1-six-redis1.nsls2.bnl.gov"
redis_host[hxn]="xf03id1-hxn-redis1.nsls2.bnl.gov"
redis_host[xfm]="xf04bm-xfm-redis1.nsls2.bnl.gov"
redis_host[isr]="xf04id1-isr-redis1.nsls2.bnl.gov"
redis_host[srx]="xf05id2-srx-redis1.nsls2.bnl.gov"
redis_host[bmm]="xf06bm-bmm-redis1.nsls2.bnl.gov"
redis_host[qas]="xf07bm-qas-redis1.nsls2.bnl.gov"
redis_host[haxpes]="xf07id1-haxpes-redis1.nsls2.bnl.gov"
redis_host[nexafs]="xf07id1-nexafs-redis1.nsls2.bnl.gov"
redis_host[rsoxs]="xf07id1-rsoxs-redis1.nsls2.bnl.gov"
redis_host[ucal]="xf07id1-ucal-redis1.nsls2.bnl.gov"
redis_host[tes]="xf08bm-tes-redis1.nsls2.bnl.gov"
redis_host[iss]="xf08id1-iss-redis1.nsls2.bnl.gov"
redis_host[cdi]="xf09id1-cdi-redis1.nsls2.bnl.gov"
redis_host[ixs]="xf10id1-ixs-redis1.nsls2.bnl.gov"
redis_host[chx]="xf11id1-chx-redis1.nsls2.bnl.gov"
redis_host[cms]="xf11bm-cms-redis1.nsls2.bnl.gov"
redis_host[opls]="xf12id1-opls-redis1.nsls2.bnl.gov"
redis_host[smi]="xf12id2-smi-redis1.nsls2.bnl.gov"
redis_host[lix]="xf16id1-lix-redis1.nsls2.bnl.gov"
redis_host[xfp]="xf17bm-xfp-redis1.nsls2.bnl.gov"
redis_host[amx]="xf17id1-amx-redis1.nsls2.bnl.gov"
redis_host[fmx]="xf17id2-fmx-redis1.nsls2.bnl.gov"
redis_host[fxi]="xf18id1-fxi-redis1.nsls2.bnl.gov"
redis_host[nyx]="xf19id2-nyx-redis1.nsls2.bnl.gov"
redis_host[arpes]="xf21id1-arpes-redis1.nsls2.bnl.gov"
redis_host[xpeem]="xf21id1-xpeem-redis1.nsls2.bnl.gov"
redis_host[csx]="xf23id1-csx-redis1.nsls2.bnl.gov"
redis_host[ios]="xf23id2-ios-redis1.nsls2.bnl.gov"
redis_host[hex]="xf27id1-hex-redis1.nsls2.bnl.gov"
redis_host[pdf]="xf28id1-pdf-redis1.nsls2.bnl.gov"
redis_host[xpd]="xf28id2-xpd-redis1.nsls2.bnl.gov"
redis_host[xpdd]="xf28id2-xpdd-redis1.nsls2.bnl.gov"
redis_host[tst]="xf31id1-tst-redis1.nsls2.bnl.gov"


REDIS_HOST=${redis_host[$ENDSTATION]}


# Variables ----------------------------------------------------------------------------------------------------
TILED_SERVER_API_KEY_VAR="TILED_BLUESKY_WRITING_API_KEY_${ENDSTATION^^}"
TILED_SERVER_API_KEY="${!TILED_SERVER_API_KEY_VAR:-secret}"
profile_location="/nsls2/data/${ENDSTATION}/shared/config/bluesky/profile_collection"
export profile_location="${profile_location}"

# Generate Certificates -------------------------------------------------------------
mkdir -p "$certdir"

echo "[hexsim] generating new Redis TLS certificate..."
openssl req -x509 -nodes -days 1 -newkey rsa:2048 \
    -keyout "$certdir/redis-${ENDSTATION}.key" \
    -out "$certdir/redis-${ENDSTATION}.crt" \
    -subj "/CN=${REDIS_HOST}" \
    -addext "subjectAltName=DNS:${REDIS_HOST},DNS:localhost,DNS:hexsim-redis,IP:127.0.0.1"
chmod 644 "$certdir/redis-${ENDSTATION}.key" "$certdir/redis-${ENDSTATION}.crt"

echo "[hexsim] generating new tiled TLS certificate..."
openssl req -x509 -newkey rsa:2048 -sha256 -days 1 -nodes \
    -keyout "$certdir/tiled.key" \
    -out "$certdir/tiled.crt" \
    -subj "/CN=tiled.nsls2.bnl.gov" \
    -addext "subjectAltName=DNS:tiled.nsls2.bnl.gov,DNS:api.nsls2.bnl.gov,IP:127.0.0.1"
chmod 644 "$certdir/tiled.key" "$certdir/tiled.crt"

# 2. START CONTAINERS (Now they boot with valid certs in place) ------------------------------------------------
docker compose -f "${compose_file}" up -d --wait --build base redis mongo

docker exec hexsim-base sh -lc ': > /etc/bluesky/redis.secret'

REDIS_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' hexsim-redis)
HOST_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' hexsim-base)
echo "[hexsim] Redis IP address: ${REDIS_IP}"
echo "[hexsim] Host IP address: ${HOST_IP}"

docker exec -it --user root hexsim-base bash -c "echo '${REDIS_IP} ${REDIS_HOST}' >> /etc/hosts"
docker exec -it --user root hexsim-base bash -lc '
    for i in 1 2 3; do
        echo "127.0.0.1 mongo${i}.nsls2.bnl.gov" >> /etc/hosts
    done
# '
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
# docker exec hexsim-base rm -rf "${profile_location}"
docker exec hexsim-base mkdir -p "${profile_location}"
docker cp "${TMP_REPO}/." "hexsim-base:${profile_location}/"

# Required scripts for the beamline setup --------------------------------------------------------------------
if [[ "${ENDSTATION}" =~ ^(fxi)$ ]]; then
    echo "Running beamline-specific setup for ${ENDSTATION}..."
    docker exec hexsim-base bash -lc "cd ${profile_location} && source .ci/bl-specific.sh"
fi

docker exec -it hexsim-base mkdir -v -p /nsls2/data/${ENDSTATION}/legacy

# OPLS soecific
if [[ "${ENDSTATION}" = "opls" ]]; then
    docker cp "${root}/configs/opls_attenuators_database.csv" "hexsim-base:/tmp/opls_attenuators_database.csv"
    docker exec -it hexsim-base mkdir -p "/nsls2/data/smi/opls/shared/config/operations/bsui_parameters/attenuators/"
    docker exec -it hexsim-base cp "/tmp/opls_attenuators_database.csv" "/nsls2/data/smi/opls/shared/config/operations/bsui_parameters/attenuators/"
fi

if [[ "${ENDSTATION}" = "srx" ]]; then
    export LOGS_HOME="/home/xf05id1"
    docker exec -it hexsim-base mkdir -v -p /home/xf05id1/
    docker exec -it hexsim-base chown -v --reference=/nsls2/ /home/xf05id1/
    docker exec -it hexsim-base mkdir -v -p /home/xf05id1/.cache/bluesky/log/
fi

docker exec hexsim-base redis-cli -h hexsim-redis -p 6380 --tls --insecure set "cycle" '"2025-2"'
docker exec hexsim-base redis-cli -h hexsim-redis -p 6380 --tls --insecure set "data_session" '"pass-000000"'

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
              uri: mongodb://hexsim-mongo:27017/metadatastore-local
              asset_registry_uri: mongodb://hexsim-mongo:27017/asset-registry-local
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

docker exec hexsim-base rm -rf "/root/.ipython/profile_test"
docker exec -it hexsim-base mkdir -p "/root/.ipython/profile_test/"
docker exec hexsim-base mkdir -p "${profile_location}/scripts"
docker cp "${root}/scripts/bsui.py" "hexsim-base:${profile_location}/scripts/bsui.py"

# Runs bsui.py interactively within the base docker container ---------------------------------------------------

# TODO: Is there a better way of dealing with all of these export statement through a .env file?
docker exec -it hexsim-base bash -lc "
cd ${profile_location}
if [[ ! -e /tmp/.X99-lock ]]; then
    Xvfb :99 -ac -screen 0 1280x1024x16 >/tmp/xvfb.log 2>&1 &
fi
export DISPLAY=:99
export MPLBACKEND=Agg
export QT_QPA_PLATFORM=offscreen
export PYTHONFAULTHANDLER=1
export LIBGL_ALWAYS_SOFTWARE=1
export QTWEBENGINE_DISABLE_SANDBOX=1
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export BLUESKY_KAFKA_BOOTSTRAP_SERVERS=127.0.0.1:9092
export BLUESKY_KAFKA_PASSWORD=test
export BEAMLINE_ACRONYM=${ENDSTATION}
export ENDSTATION_ACRONYM=${ENDSTATION}
export TILED_BLUESKY_WRITING_API_KEY_${ENDSTATION^^}=secret
export TILED_BLUESKY_WRITING_API_KEY=secret
export TILED_SERVER_API_KEY=${TILED_SERVER_API_KEY}
export TILED_API_KEY=${TILED_SERVER_API_KEY}
pixi run -e terminal ipython --profile=test --pdb -i ${profile_location}/scripts/bsui.py
"

wait

docker compose -f "${compose_file}" down


exit 0