# Provision the ELMS infrastructure using Terraform

[Terraform](https://www.terraform.io/) can be used for managing the ELMS infrastructure on Azure. You can find the definitions in the [terraform](../terraform) folder.
Terraform can be set up locally and resources can be deployed to a chosen Azure subscription.
The following steps are needed to achieve this:

## 1. Prepare environment

### Option 1: Use Docker devcontainer

1. Install [Docker Desktop](https://docs.docker.com/desktop/)
2. Install Visual Studio extension [Remote - Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
3. Open project in a devcontainer. Run the `Remote-Containers: Open Folder in Container...` command and select the local folder

After that you will have all the needed tools, so continue with [step 3](#3-create-the-terraform-state-storage).

### Option 2: Install Terraform and Azure CLI manually

1. [Install Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
2. [Install Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)

## 2. Log into Azure CLI

Open a terminal, run the following commands and, if needed, select the Azure subscription which will be targeted by the Terraform deployment:

```shell
az login
az account set --subscription="<subscription_id>"
```

## 3. Create the Terraform state storage

When running Terraform for the first time against an Azure subscription, the backend must be created. In the existing Terraform configuration, the backend will be stored in Azure as it provides additional security for the state file. It consists of an Azure storage account and a container which will be used to store the Terraform state file. It is important to note that this storage account will not be managed by Terraform and must be created manually. The storage account name must be globally unique within Azure.

The Terraform backend can be set up by running the `init-tfstate-storage.sh` script, located in the `terraform/scripts` folder and providing the required parameters (`resource_group_name=$1`, `location=$2`, `storage_account_name=$3`).

```shell
cd terraform/scripts
./init-tfstate-storage.sh "<resource_group_name>" "<location>" "<storage_account_name>"
```

Should a user prefer to not use an Azure storage account and store the Terraform backend locally, then the following code snippet must be removed from the `terraform/environment/main.tf` and the above script won't be required anymore.

```shell
provider "azurerm" {
  features {}
}
```

## 4. Terraform init

After successfully creating the backend, the Terraform code is ready to be initialized. The `storage_account_name` is the name of the storage account created in the previous step. The other necessary variables are taken from the `backend.tfvars` file which contains the values used in the `init-tfstate-storage.sh` script.

```shell
cd infra/terraform/environment
terraform init -backend-config=backend.tfvars -backend-config=storage_account_name="<storage_account_name>"
```

## 5. Terraform apply

The actual provisioning of the resources happens in this step. The command will display what are the differences between the terraform state file and the new local changes and will prompt manual input of the response `yes` to begin provisioning.

It is possible that this command has an impact on the pre-existent IoT Hub so make sure to carefully review the Terraform plan before agreeing to the changes.

This command requires several parameters, specifically those that do not have a default value assigned in the `environment/variable.tf` file.

```shell
cd terraform/environment
terraform apply -var location="<location>" -var rg_name="<rg-name>" -var iothub_id="<iothub-resource-id>" -var iothub_name="<iothub-name>"
```

If you want to use the [Monitoring architecture](../README.md#monitoring-architecture-reference), then you need to change the default value of the following variable: `send_metrics_device_to_cloud=true`.

```shell
cd terraform/environment
terraform apply -var location="<location>" -var rg_name="<rg-name>" -var iothub_id="<iothub-resource-id>" -var iothub_name="<iothub-name>" -var send_metrics_device_to_cloud=true
```

The default values of any other variables can be overridden by specifying additional parameters in the `apply` command.

## 6. Specify IoT edge devices you want to capture logs from

Add the tag `logPullEnabled="true"` to your IoT edge devices' twins to allow log pulling from the modules. This can be done in the Azure Portal or with the following command:

```shell
az iot hub device-twin update --device-id <edge_device_name> --hub-name <iothub_name> --tags '{"logPullEnabled": "true"}'
```

## 7. Terraform destroy

The entire infrastructure can be deleted by running:

```shell
cd infra/terraform/environment/
terraform destroy
```

## 8. Additional resources

- [Azure Terraform provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Terraform CLI](https://www.terraform.io/docs/cli/commands/index.html)
