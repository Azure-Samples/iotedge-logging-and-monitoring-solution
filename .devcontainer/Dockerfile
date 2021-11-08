# See here for image contents: https://github.com/microsoft/vscode-dev-containers/tree/v0.140.1/containers/dotnetcore/.devcontainer/base.Dockerfile

# Dependencies versions
ARG PYTHON_VERSION="3.7.10"

FROM python:${PYTHON_VERSION}-buster

# Dependencies versions
ARG MD_SPELLCHECK_VERSION="1.3.1"
ARG MD_LINK_CHECK_VERSION="3.8.6"
ARG MD_LINT_VERSION="0.27.1"
ARG TERRAFORM_VERSION="0.14.7"
ARG TFLINT_VERSION="0.22.0"
ARG DOTENV_CLI_VERSION="4.0.0"
ARG DOCKER_COMPOSE_VERSION="1.28.5"

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential curl unzip jq && \
    # Install node and npm
    apt-get install -y nodejs npm && \
    # Install the Azure CLI and IoT extension
    curl -sL https://aka.ms/InstallAzureCLIDeb | bash && \
    az extension add --name azure-iot && \
    # Install Docker CE CLI
    apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common lsb-release && \
    curl -fsSL https://download.docker.com/linux/$(lsb_release -is | tr '[:upper:]' '[:lower:]')/gpg | apt-key add - 2>/dev/null && \
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/$(lsb_release -is | tr '[:upper:]' '[:lower:]') $(lsb_release -cs) stable" && \
    apt-get update && \
    apt-get install -y docker-ce-cli && \
    # Install markdown linters
    npm install markdown-spellcheck@${MD_SPELLCHECK_VERSION} -g && \
    npm install markdown-link-check@${MD_LINK_CHECK_VERSION} -g && \
    npm install markdownlint-cli@${MD_LINT_VERSION} -g && \
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
    #
    # Clean up
    apt-get autoremove -y && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*

# Customize bash
RUN \
    # Git command prompt
    git clone https://github.com/magicmonty/bash-git-prompt.git ~/.bash-git-prompt --depth=1 && \
    echo "if [ -f \"$HOME/.bash-git-prompt/gitprompt.sh\" ]; then GIT_PROMPT_ONLY_IN_REPO=1 && source $HOME/.bash-git-prompt/gitprompt.sh; fi" >> "/root/.bashrc" && \
    # Install bash completion
    apt-get update && \
    apt-get -y install bash-completion && \
    echo "source /usr/share/bash-completion/bash_completion" >> ~/.bashrc 
