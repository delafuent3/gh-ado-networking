terraform {
  backend "azurerm" {
    # All values injected via -backend-config flags in the pipeline.
    # See .azure/templates/steps-validate.yml and steps-deploy.yml.
    # Manual init example:
    #   terraform init \
    #     -backend-config="resource_group_name=rg-terraform-state" \
    #     -backend-config="storage_account_name=<your-storage-account>" \
    #     -backend-config="container_name=dev" \
    #     -backend-config="key=networking.tfstate"
  }
}