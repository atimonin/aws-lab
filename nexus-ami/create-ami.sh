#!/bin/sh

# make image

terraform plan -var-file=nexus-template-vm.tfvars -out=nexus-template-vm.tfplan
terraform apply nexus-template-vm.tfplan

# save resources id's
echo export NEXUS_AMI_ID=$(terraform output nexus_ami_id) > nexus_ids
echo export NEXUS_EFS_ID=$(terraform output nexus_EFS_store_id) >> nexus_ids
# cleanup uneeded resources

terraform state rm aws_ami_from_instance.nexus_template_ami
terraform state rm aws_efs_file_system.nexus_store

terraform destroy -var-file=nexus-template-vm.tfvars -auto-approve
