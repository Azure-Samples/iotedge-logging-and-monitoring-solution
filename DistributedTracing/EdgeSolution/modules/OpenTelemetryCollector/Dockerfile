
# FROM otel/opentelemetry-collector-contrib-dev
FROM otelcontribcol:latest


COPY ./otel-collector-config.yml ./etc/otel/config.yaml 

ENV JAEGER_ENDPOINT="http://host.docker.internal:14268/api/traces"