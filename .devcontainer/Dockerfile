# See here for image contents: https://github.com/microsoft/vscode-dev-containers/tree/v0.194.0/containers/dotnet/.devcontainer/base.Dockerfile
FROM mcr.microsoft.com/vscode/devcontainers/dotnet:0-3.1

# Dependencies versions
ARG TERRAFORM_VERSION="0.14.7"
ARG TFLINT_VERSION="0.22.0"

# Install Docker CE
COPY library-scripts/*.sh /tmp/library-scripts/
RUN \
    apt-get update -y && \
    # Use Docker script from script library to set things up - enable non-root docker, user vscode, using moby
    /bin/bash /tmp/library-scripts/docker-in-docker-debian.sh "true" "automatic" "true" && \
    # Install iotedgehubdev
    apt-get install -y python3-pip && pip3 install iotedgehubdev && \
    # Install Azure Function Core Tools
    mkdir -p /opt/azfunctools && \
    cd /opt/azfunctools && \
    curl -sSL -o azfunctools.zip https://github.com/Azure/azure-functions-core-tools/releases/download/4.0.3971/Azure.Functions.Cli.linux-x64.4.0.3971.zip && \
    unzip azfunctools.zip && \
    chmod +x func && \
    chmod +x gozip && \
    # Install the Azure CLI and IoT extension
    curl -sL https://aka.ms/InstallAzureCLIDeb | bash && \
    az extension add --name azure-iot && \
    # Install Terraform
    mkdir -p /tmp/docker-downloads && \
    curl -sSL -o /tmp/docker-downloads/terraform.zip https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip && \
    unzip /tmp/docker-downloads/terraform.zip && \
    mv terraform /usr/local/bin && \
    # Install tflint
    curl -sSL -o /tmp/docker-downloads/tflint.zip https://github.com/wata727/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_amd64.zip && \
    unzip /tmp/docker-downloads/tflint.zip && \
    mv tflint /usr/local/bin && \
    # Clean up downloaded files
    cd ~ && \
    rm -rf /tmp/* && \
    # Clean up
    apt-get autoremove -y && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*

ENV PATH="/opt/azfunctools:${PATH}"

# launch docker-ce
ENTRYPOINT [ "/usr/local/share/docker-init.sh" ]
CMD [ "sleep", "infinity" ]
