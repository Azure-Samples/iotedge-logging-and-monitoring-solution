#!/bin/bash

set -exo pipefail

if [ "$#" -ne 3 ]
then
	echo "Script requires 3 parameters: resource_group_name, location, storage_account_name"
	exit 1
fi

resource_group_name=$1
location=$2
storage_account_name=$3

echo "Create/Reuse resource group $resource_group_name in $location..."
az group create -n "$resource_group_name" -l "$location"
echo "Created/Reusing resource group $resource_group_name in $location."

echo "Create/Reuse storage account $storage_account_name..."
az storage account create -n "$storage_account_name" -g "$resource_group_name" -l "$location"
echo "Created/Reusing storage account $storage_account_name."

echo "Create/Reuse storage container tfstate in $storage_account_name..."
key=$(az storage account keys list -g "$resource_group_name" -n "$storage_account_name" --query "[0].value" -o tsv)
az storage container create -n "tfstate" --account-name "$storage_account_name" --account-key "$key"
echo "Created/Reusing storage container tfstate in $storage_account_name."
