mustache ENV config-template.yaml > config.yaml

cat config.yaml

./otelcontribcol --config config.yaml