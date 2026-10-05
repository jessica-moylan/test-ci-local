FROM python:3.11-slim

# Try making the docker image be REHL based
# sudo is required for paths that are created within the profile collections
RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo \
    curl \
    bash \
    ca-certificates \
    git \
    build-essential \
    redis-tools \
    xvfb \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL https://pixi.sh/install.sh | sh \
 && mv /root/.pixi/bin/pixi /usr/local/bin/pixi

RUN pip install --no-cache-dir -U caproto

ENV EPICS_CA_AUTO_ADDR_LIST=NO
ENV EPICS_CA_ADDR_LIST=127.0.0.1:5064

ARG ENDSTATION
ENV ENDSTATION=${ENDSTATION}

ARG profile_location
ENV profile_location=${profile_location}

COPY scripts/spoof_beamline.py /usr/local/bin/spoof_beamline.py

WORKDIR ${profile_location}
COPY . ${profile_location}

# Bemaline specific configuration using entrypoint script
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["python", "/usr/local/bin/spoof_beamline.py"]

