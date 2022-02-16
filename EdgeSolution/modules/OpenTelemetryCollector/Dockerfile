
# FROM otel/opentelemetry-collector-contrib-dev
FROM otelcontribcol:latest as prep

FROM alpine:latest

WORKDIR /otel

COPY --from=prep otelcontribcol otelcontribcol

RUN wget https://github.com/quantumew/mustache-cli/releases/download/v1.0.0/mustache-cli-linux-amd64.zip && \
    unzip mustache-cli-linux-amd64.zip && \
    mkdir -p -m 775 /usr/local/bin && \
    mv mustache /usr/local/bin/mustache



COPY ./start.sh start.sh


COPY ./otel-collector-config.yml config-template.yaml 

ENTRYPOINT ./start.sh

