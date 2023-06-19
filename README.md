# GCP VM Migrator
This utility automates the migration of Virtual Machine instances within GCP. It creates a Terraform configuration of your GCP environment, which can be replicated in any project/region/VPC/subnet.

## Prerequisites
hcledit cli tool (https://github.com/minamijoyo/hcledit)
gcloud cli tool
gsed
terraform

## Permissions
The gcp account with which you are running this script should have the ability to:
* Create/Delete/Shutdown GCE VMs
* Create/Delete VPC subnets
* Create/Delete machine images
Recommended roles:
* Compute Admin  (roles/compute.admin) https://cloud.google.com/iam/docs/understanding-roles#compute.admin
* Cloud Asset Service Agent (roles/cloudasset.serviceAgent) https://cloud.google.com/iam/docs/understanding-roles#cloudasset.serviceAgent

## Quotas
Verify that the required quotas are properly configured for the migration.
These include:
* Read operations (10k without approval)
* Read operations per region (10k without approval)
* Cpu per region (5k without approval)
* Persistent Disk SSD (GB) per region
* Global resource mutation requests per minute
* Operation read requests per minute per region
* Operation read requests

---
## Preparation
1. Define the variables  
Define the `SOURCE_PROJECT` variable in Makefile. 
1. Do resource export in terraform format  
Run `make export_infrastructure`
This will export the resources mentioned in `GCP_RESOURCE_TYPE` (defaults to: ComputeDisk, ComputeInstance, ComputeSubnetwork) to your terraform `TF_SOURCE` source folder (`tf-source` by default). 
1. Update the terraform files  
Run `make update_terraform`
This command will create `TF_TARGET` folder (`tf-target` by default). Then it will copy over the files from `TF_SOURCE` folder rearranging terraform files to the folders by project_id/resource_type/vpc/subnet/zone
1. Prepare migration config  
In `TF_TARGET` folder comment out everything in `main.tf` file. For each module in main.tf configure the `project, region, zone, network, subnet` accordingly.
1. Create initial PD snapshots  
In `main.tf` uncomment <project_id>-ComputeSnapshot-... modules for the disks you want to migrate. 
Run `make tf_target_apply`
---
## Modifying source resources
During the migration you will need to also modify source VMs. You can use either terraform or original vm-migrator approach.
For terraform approach:
1. Import source environment into terraform state  
Run `make tf_source_import`
1. Configure boot PDs to not be deleted on instance removal  
Run `make keep_boot_disks` and then `make tf_source_apply`. Keep in mind that this will trigger source VMs recreation.
---
## Migration
1. Stop running VMs  
For terraform approach:
Run `make stop_vms` and then `make tf_source_apply`
1. Do final PD snapshots  
Run `make add_snapshot` 
Then run `make tf_target_apply`
1. Create PDs from snapshot  
Run `make update_disk_source` 
In `main.tf` uncomment <project_id>-ComputDisk-... modules for the Disks you want to migrate.
Run `make tf_target_apply `
1. Delete source VMs  
From the `main.tf` file in the `TF_SOURCE` folder comment out module blocks with VMs you want to remove.
Run `make tf_source_apply`
1. Delete VPC subnets  
From the `main.tf` file in the `TF_SOURCE` folder comment out module blocks with Subnets you want to remove.
Run `make tf_source_apply`
1. Create VPC subnets  
In the `main.tf` file in the `TF_TARGET` folder uncomment <project_id>-ComputeSubnet-... for the subnets you want to create in target destination
1. Create VMs  
In the `main.tf` file in the `TF_TARGET` folder uncomment <project_id>-ComputInstance-... for the subnets you want to create in target destination