# Copyright 2021 Google LLC. This software is provided as-is,
# without warranty or representation for any use or purpose.
# Your use of it is subject to your agreement with Google.

TF_EXPORT_PATH="sap-copy"
GCP_RESOURCE_TYPE="ComputeDisk,ComputeInstance"
SOURCE_PROJECT="sap-development"

export_infrastructure:
	gcloud beta resource-config bulk-export \
	--quiet \
	--project=${SOURCE_PROJECT} \
	--path=${TF_EXPORT_PATH} \
	--resource-types=${GCP_RESOURCE_TYPE} \
	--resource-format=terraform

move_files:
	#move vm tf files from projects/${project}/ComputeInstance/${zone} to projects/${project}/ComputeInstance/${zone}/${network}/${subnet}
	TF_FILES=$$(find ./${TF_EXPORT_PATH} -type f -name "*.tf" | grep 'ComputeInstance/[a-zA-Z0-9_-]*/[a-zA-Z0-9_-]*.tf'); \
	for TF_FILE_PATH in $${TF_FILES}; do \
		echo TF_FILE_PATH: $${TF_FILE_PATH}; \
		gsed -i -E "/startup-script *= /s/[\$$]/\$$\$$/g"  $${TF_FILE_PATH}; \
		gsed -i -E "/startup-script *= /s/%/%%/g"  $${TF_FILE_PATH}; \
		TF_FILE_NAME=$$(basename $${TF_FILE_PATH} .tf); \
		TF_VM_NAME=$$(gsed -nE 's/resource "google_compute_instance" "([a-zA-Z0-9_]*)" \{/\1/pi' $${TF_FILE_PATH}); \
		TF_DIR_NAME=$$(dirname $${TF_FILE_PATH}); \
		echo TF_DIR_NAME: $${TF_DIR_NAME}; \
		echo TF_VM_NAME: $${TF_VM_NAME}; \
		FULL_NETWORK=$$(hcledit attribute get resource.google_compute_instance.$${TF_VM_NAME}.network_interface.network -f $${TF_FILE_PATH}); \
		FULL_SUBNET=$$(hcledit attribute get resource.google_compute_instance.$${TF_VM_NAME}.network_interface.subnetwork -f $${TF_FILE_PATH}); \
		NETWORK=$$(basename $${FULL_NETWORK} | tr -d '"'); \
		SUBNET=$$(basename $${FULL_SUBNET} | tr -d '"'); \
		ZONE=$$(basename $${TF_DIR_NAME}); \
		BOOT_DISK_NAME=$$(hcledit attribute get resource.google_compute_instance.$${TF_VM_NAME}.boot_disk.source -f $${TF_FILE_PATH} | tr -d '"'); \
		ATTACHED_DISKS=$$(hcledit block get resource.google_compute_instance.$${TF_VM_NAME}.attached_disk -f $${TF_FILE_PATH} | grep source | cut -d '"' -f2 ); \
		TF_DIR_NAME_WITHOUT_ZONE=$$(dirname $${TF_DIR_NAME}); \
		echo NETWORK: $${NETWORK}; \
		echo SUBNET: $${SUBNET}; \
		echo ZONE: $${ZONE}; \
		BOOT_DISK_NAME=$${BOOT_DISK_NAME##*\/}; \
		BOOT_DISK_NAME=$${BOOT_DISK_NAME//--/-}; \
		echo BOOT_DISK_NAME: $${BOOT_DISK_NAME}; \
		echo ATTACHED_DISKS: $${ATTACHED_DISKS}; \
		TF_NEW_PATH=$${TF_DIR_NAME_WITHOUT_ZONE}/$${NETWORK}/$${SUBNET}/$${ZONE}; \
		echo TF_NEW_PATH: $${TF_NEW_PATH}; \
		mkdir -p $${TF_NEW_PATH}; \
		mv $${TF_FILE_PATH} $${TF_NEW_PATH}/$${TF_FILE_NAME}.instance.tf ;\
		mv ./${TF_EXPORT_PATH}/${SOURCE_PROJECT}/ComputeDisk/$${ZONE}/$${BOOT_DISK_NAME}.tf $${TF_NEW_PATH}/$${TF_FILE_NAME}.$${BOOT_DISK_NAME}.disk.tf; \
		for ATTACHED_DISK in $${ATTACHED_DISKS}; do \
			ATTACHED_DISK=$${ATTACHED_DISK##*\/}; \
			ATTACHED_DISK=$${ATTACHED_DISK//--/-}; \
			mv ./${TF_EXPORT_PATH}/${SOURCE_PROJECT}/ComputeDisk/$${ZONE}/$${ATTACHED_DISK}.tf $${TF_NEW_PATH}/$${TF_FILE_NAME}.$${ATTACHED_DISK}.disk.tf; \
		done; \
	done; \
	#for TF_FILE_PATH in $${TF_FILES}; do \
		#rm -rf $$(dirname $${TF_FILE_PATH}); \
	#done; \
	#rm -rf  ./${TF_EXPORT_PATH}/${SOURCE_PROJECT}; \	

update_vms:
	# find ./${TF_EXPORT_PATH} -type f -name '*.tf' -exec sed -i "" -e "s/ zone *= \".*\"/ zone = var.zone/g" {} +
	# find ./${TF_EXPORT_PATH} -type f -name '*.tf' -exec sed -i "" -e "s/ region *= \".*\"/ region = var.region/g" {} +
	# find ./${TF_EXPORT_PATH} -type f -name '*.tf' -exec sed -i "" -e "s/ project *= \".*\"/ project = var.project/g" {} +

	TF_FILES=$$(find ./${TF_EXPORT_PATH} -type f -name "*.tf" | grep .instance.tf); \
	for TF_FILE in $${TF_FILES}; do \
		TF_VM_NAME=$$(basename $${TF_FILE//-/_} .instance.tf); \
		echo TF_FILE: $${TF_FILE}; \
		VM_NAME=$$(hcledit attribute get resource.google_compute_instance.$${TF_VM_NAME}.name --file $${TF_FILE}); \
		hcledit attribute set resource.google_compute_instance.$${TF_VM_NAME}.zone var.zone --file $${TF_FILE} --update; \
		hcledit attribute set resource.google_compute_instance.$${TF_VM_NAME}.project var.project --file $${TF_FILE} --update; \
		hcledit attribute set resource.google_compute_instance.$${TF_VM_NAME}.network_interface.subnetwork_project var.project --file $${TF_FILE} --update; \
		hcledit attribute set resource.google_compute_instance.$${TF_VM_NAME}.network_interface.network \"https://www.googleapis.com/compute/v1/projects/$$\{var.project\}/global/networks/$$\{var.network\}\" --file $${TF_FILE} --update; \
		hcledit attribute set resource.google_compute_instance.$${TF_VM_NAME}.network_interface.subnetwork \"https://www.googleapis.com/compute/v1/projects/$$\{var.project\}/regions/$$\{var.region\}/subnetworks/$$\{var.subnet\}\" --file $${TF_FILE} --update; \
		hcledit attribute append resource.google_compute_instance.$${TF_VM_NAME}.desired_status \"RUNNING\" --file $${TF_FILE} --update; \
		gsed -i -E "s/source *= \"https:\/\/www.googleapis.com\/compute\/v1\/projects\/[a-zA-Z0-9-]*\/zones\/[a-zA-Z0-9-]*\/disks\/([a-zA-Z0-9-]*)\"/source = google_compute_disk.\1.name/g" $${TF_FILE}; \
		gsed -i -E ":loop; s/google_compute_disk.([^-]*)-(.*).name/google_compute_disk.\1_\2.name/g; t loop" $${TF_FILE}; \
		gsed -i "/initialize_params {/,/^    }/d" $${TF_FILE}; \
		gsed -i "s/ network_ip/ #network_ip/g" $${TF_FILE}; \
		gsed -i "s/ nat_ip/ #nat_ip/g" $${TF_FILE}; \
		gsed -i "/reservation_affinity {/,/^  }/d" $${TF_FILE}; \
		hcledit attribute set resource.google_compute_instance.$${TF_VM_NAME}.machine_type \"f1-micro\" --file $${TF_FILE} --update; \
		hcledit attribute set resource.google_compute_instance.$${TF_VM_NAME}.service_account.email \"vm-migration-test@movsic-test.iam.gserviceaccount.com\" --file $${TF_FILE} --update; \
	done;

update_disks:
	TF_FILES=$$(find ./${TF_EXPORT_PATH} -type f -name "*.tf" | grep .disk.tf); \
	for TF_FILE in $${TF_FILES}; do \
		TF_DISK_NAME=$$(basename $${TF_FILE//-/_} .disk.tf); \
		TF_DISK_NAME=$${TF_DISK_NAME##*.}; \
		echo TF_FILE: $${TF_FILE}; \
		hcledit attribute set resource.google_compute_disk.$${TF_DISK_NAME}.zone var.zone --file $${TF_FILE} --update; \
		hcledit attribute set resource.google_compute_disk.$${TF_DISK_NAME}.project var.project --file $${TF_FILE} --update; \
		hcledit attribute set resource.google_compute_disk.$${TF_DISK_NAME}.image \"https://www.googleapis.com/compute/beta/projects/debian-cloud/global/images/debian-11-bullseye-v20230509\" --file $${TF_FILE} --update; \
		hcledit attribute set resource.google_compute_disk.$${TF_DISK_NAME}.size 10 --file $${TF_FILE} --update; \
	done;

generate_tf_files:
	rm -rf ./main.tf;
	MODULE_PATHS=$$(find ${TF_EXPORT_PATH} -type f -name "*.tf" | xargs -I% dirname % | sort -u); \
	for MODULE_PATH in $${MODULE_PATHS}; do \
		echo MODULE_PATH: $${MODULE_PATH}; \
		echo "variable \"project\" {}\n \
			variable \"region\" {}\n \
			variable \"zone\" {}\n \
			variable \"network\" {}\n \
			variable \"subnet\" {}\n \
			variable \"source_project\" {}\n \
			variable \"source_region\" {}\n \
			variable \"source_zone\" {}\n \
			variable \"source_network\" {}\n \
			variable \"source_subnet\" {}\n \
			" > $${MODULE_PATH}/variables.tf; \
		MODULE_PATH_ARR=($${MODULE_PATH//\// }); \
		echo $${MODULE_PATH_ARR[0]}; \
		echo "module \"$${MODULE_PATH//\//_}\"{\n \
			source = \"./$${MODULE_PATH}\"\n \
			source_project=\"$${MODULE_PATH_ARR[2]}\"\n \
			source_region=\"$${MODULE_PATH_ARR[6]%-*}\"\n \
			source_zone=\"$${MODULE_PATH_ARR[6]}\"\n \
			source_network=\"$${MODULE_PATH_ARR[4]}\"\n \
			source_subnet=\"$${MODULE_PATH_ARR[5]}\"\n \
			project=\"${TARGET_PROJECT}\"\n \
			region=\"${TARGET_REGION}\"\n \
			zone=\"${TARGET_ZONE}\"\n \
			network=\"${TARGET_NETWORK}\"\n \
			subnet=\"${TARGET_SUBNET}\"\n \
		}" >> ./main.tf; \
	done;

add_snapshots:
	TF_FILES=$$(find ./${TF_EXPORT_PATH} -type f -name "*.tf" | grep ComputeDisk); \
	echo $${TF_FILES}; \
	for TF_FILE in $${TF_FILES}; do \
		TF_DISK_NAME=$$(basename $${TF_FILE//-/_} .tf); \
		echo TF_DISK_NAME: $${TF_DISK_NAME}; \
		if [ "$${TF_DISK_NAME}" == "variables" ]; then \
			echo "Variable file -> skipping"; \
			continue; \
		fi; \
		gsed -i "/data \"google_compute_disk\" \"$${TF_DISK_NAME}_disk\" {/,/^  }/d" $${TF_FILE}; \
		gsed -i "/data \"google_compute_snapshot\" \"$${TF_DISK_NAME}_snapshot_init\" {/,/^  }/d" $${TF_FILE}; \
		hcledit attribute append resource.google_compute_disk.$${TF_DISK_NAME}.snapshot google_compute_snapshot.$${TF_DISK_NAME}_snapshot_init.id --newline --file $${TF_FILE} --update; \
		hcledit attribute set resource.google_compute_disk.$${TF_DISK_NAME}.snapshot google_compute_snapshot.$${TF_DISK_NAME}_snapshot_init.id --file $${TF_FILE} --update; \
		hcledit attribute rm resource.google_compute_disk.$${TF_DISK_NAME}.image --file $${TF_FILE} --update; \
		echo "data \"google_compute_disk\" \"$${TF_DISK_NAME}_disk\" {\n \
			name    = \"$${TF_DISK_NAME//_/-}\"\n \
			project = var.project\n \
			zone = var.source_zone\n \
		}" >> $${TF_FILE}; \
		echo "resource \"google_compute_snapshot\" \"$${TF_DISK_NAME}_snapshot_init\" {\n \
			name = \"$${TF_DISK_NAME//_/-}-snapshot-init\"\n \
			source_disk = data.google_compute_disk.$${TF_DISK_NAME}_disk.id\n \
			zone = var.zone\n \
			project = var.project\n \
			storage_locations = [var.region]\n \
		}" >> $${TF_FILE}; \
	done;

stop_vms:
	TF_FILES=$$(find ./${TF_EXPORT_PATH} -type f -name "*.tf" | grep ComputeInstance); \
	for TF_FILE in $${TF_FILES}; do \
		TF_VM_NAME=$$(basename $${TF_FILE//-/_} .tf); \
		hcledit attribute set resource.google_compute_instance.$${TF_VM_NAME}.desired_status \"TERMINATED\" --file $${TF_FILE} --update; \
	done;

start_vms:
	TF_FILES=$$(find ./${TF_EXPORT_PATH} -type f -name "*.tf" | grep ComputeInstance); \
	for TF_FILE in $${TF_FILES}; do \
		TF_VM_NAME=$$(basename $${TF_FILE//-/_} .tf); \
		hcledit attribute set resource.google_compute_instance.$${TF_VM_NAME}.desired_status \"RUNNING\" --file $${TF_FILE} --update; \
	done;

clean:
	terraform destroy --auto-approve
	rm -rf main.tf
	rm -rf ${TF_EXPORT_PATH}
	rm -rf .terraform*
	rm -rf terraform*

migrate:
	#todo brew install yq

	#https://github.com/sclevine/yj https://unix.stackexchange.com/questions/729059/read-confighaving-nested-configurationfile-using-bash
	#https://www.reddit.com/r/Terraform/comments/qfcgsv/automatically_edit_terraform_configuration_files/ hcledit

	#jq

	#hardcode vars in the module
	#add dependencies between module disks and instances

	#check how vm from different subnets are created
	#replace whole lines: project, zone, network, subnetwork, network_project
	#rename module

	#question: add disks to vm terraform file