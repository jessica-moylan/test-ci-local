FROM python:3.11-slim

RUN apt-get update && apt-get install -y curl bash ca-certificates && \
    curl -fsSL https://pixi.sh/install.sh | sh && \
    mv /root/.pixi/bin/pixi /usr/local/bin/pixi

RUN pip install --no-cache-dir -U caproto

ENV EPICS_CA_AUTO_ADDR_LIST=NO
ENV EPICS_CA_ADDR_LIST=127.0.0.1:5064

COPY scripts/spoof_beamline.py /usr/local/bin/spoof_beamline.py

WORKDIR /workspace
COPY . /workspace

CMD ["python", "/usr/local/bin/spoof_beamline.py"]

