FROM mcr.microsoft.com/dotnet/sdk:5.0 AS build-env
RUN git clone https://github.com/Azure/iotedge

WORKDIR /app
COPY *.csproj ./
RUN dotnet restore SimulatedTemperatureSensor.csproj


COPY . ./
RUN dotnet publish -c Release -o out --no-dependencies --no-restore SimulatedTemperatureSensor.csproj

FROM mcr.microsoft.com/dotnet/runtime:5.0-buster-slim
WORKDIR /app
COPY --from=build-env /app/out ./

RUN useradd -ms /bin/bash moduleuser
USER moduleuser

ENV OTLP_ENDPOINT="http://opentelemetrycollector:4317"

ENTRYPOINT ["dotnet", "SimulatedTemperatureSensor.dll"]
