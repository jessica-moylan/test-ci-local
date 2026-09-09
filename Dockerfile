FROM python:3.11-slim

RUN apt-get update && apt-get install -y curl bash ca-certificates && \
    curl -fsSL https://pixi.sh/install.sh | sh && \
    mv /root/.pixi/bin/pixi /usr/local/bin/pixi

WORKDIR /workspace
COPY . /workspace

CMD ["bash"]