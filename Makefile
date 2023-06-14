# Copyright 2023 Google LLC. This software is provided as-is,
# without warranty or representation for any use or purpose.
# Your use of it is subject to your agreement with Google.

TF_EXPORT_PATH="tf-source"
TF_TARGET_PATH="tf-target"
GCP_RESOURCE_TYPE="ComputeDisk,ComputeInstance,ComputeSubnetwork"
SOURCE_PROJECT="movsic-test"

export_infrastructure:
	gcloud beta resource-config bulk-export \
	--quiet \
	--project=${SOURCE_PROJECT} \
	--path=${TF_EXPORT_PATH} \
	--resource-types=${GCP_RESOURCE_TYPE} \
	--resource-format=terraform; \
	gcloud beta resource-config terraform generate-import ${TF_EXPORT_PATH} \
	 --output-module-file=${TF_EXPORT_PATH}/main.tf \
	 --output-script-file=${TF_EXPORT_PATH}/import.sh; \

move_files:
	rm -rf ${TF_TARGET_PATH}; \
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
		REGION=$${ZONE%-*}; \
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
		TF_VM_NEW_PATH=./${TF_TARGET_PATH}/${SOURCE_PROJECT}/ComputeInstance/$${NETWORK}/$${SUBNET}/$${ZONE}; \
		TF_DISK_NEW_PATH=./${TF_TARGET_PATH}/${SOURCE_PROJECT}/ComputeDisk/$${NETWORK}/$${SUBNET}/$${ZONE}; \
		TF_SUBNET_NEW_PATH=./${TF_TARGET_PATH}/${SOURCE_PROJECT}/ComputeSubnetwork/$${NETWORK}/$${SUBNET}/$${ZONE}; \
		echo TF_VM_NEW_PATH: $${TF_VM_NEW_PATH}; \
		mkdir -p $${TF_VM_NEW_PATH}; \
		mkdir -p $${TF_DISK_NEW_PATH}; \
		mkdir -p $${TF_SUBNET_NEW_PATH}; \
		cp $${TF_FILE_PATH} $${TF_VM_NEW_PATH}/$${TF_FILE_NAME}.tf ;\
		cp ./${TF_EXPORT_PATH}/${SOURCE_PROJECT}/ComputeDisk/$${ZONE}/$${BOOT_DISK_NAME}.tf $${TF_DISK_NEW_PATH}/$${BOOT_DISK_NAME}.tf; \
		echo ./${TF_EXPORT_PATH}/projects/${SOURCE_PROJECT}/ComputeSubnetwork/$${REGION}/$${SUBNET}.tf; \
		echo $${TF_SUBNET_NEW_PATH}/$${SUBNET}.tf; \
		cp ./${TF_EXPORT_PATH}/projects/${SOURCE_PROJECT}/ComputeSubnetwork/$${REGION}/$${SUBNET}.tf $${TF_SUBNET_NEW_PATH}/$${SUBNET}.tf; \
		for ATTACHED_DISK in $${ATTACHED_DISKS}; do \
			ATTACHED_DISK=$${ATTACHED_DISK##*\/}; \
			ATTACHED_DISK=$${ATTACHED_DISK//--/-}; \
			cp ./${TF_EXPORT_PATH}/${SOURCE_PROJECT}/ComputeDisk/$${ZONE}/$${ATTACHED_DISK}.tf $${TF_DISK_NEW_PATH}/$${ATTACHED_DISK}.tf; \
		done; \
	done; \

update_vms:
	TF_FILES=$$(find ./${TF_TARGET_PATH} -type f -name "*.tf" | grep ComputeInstance); \
	for TF_FILE in $${TF_FILES}; do \
		TF_VM_NAME=$$(basename $${TF_FILE//-/_} .tf); \
		echo TF_FILE: $${TF_FILE}; \
		echo TF_VM_NAME: $${TF_VM_NAME}; \
		VM_NAME=$$(hcledit attribute get resource.google_compute_instance.$${TF_VM_NAME}.name --file $${TF_FILE} | tr -d '"'); \
		hcledit attribute set resource.google_compute_instance.$${TF_VM_NAME}.zone var.zone --file $${TF_FILE} --update; \
		hcledit attribute set resource.google_compute_instance.$${TF_VM_NAME}.project var.project --file $${TF_FILE} --update; \
		hcledit attribute set resource.google_compute_instance.$${TF_VM_NAME}.network_interface.subnetwork_project var.project --file $${TF_FILE} --update; \
		hcledit attribute set resource.google_compute_instance.$${TF_VM_NAME}.network_interface.network \"https://www.googleapis.com/compute/v1/projects/$$\{var.project\}/global/networks/$$\{var.network\}\" --file $${TF_FILE} --update; \
		hcledit attribute set resource.google_compute_instance.$${TF_VM_NAME}.network_interface.subnetwork \"https://www.googleapis.com/compute/v1/projects/$$\{var.project\}/regions/$$\{var.region\}/subnetworks/$$\{var.subnet\}\" --file $${TF_FILE} --update; \
		gsed -i -E "s/source *= \"https:\/\/www.googleapis.com\/compute\/v1\/projects\/[a-zA-Z0-9-]*\/zones\/[a-zA-Z0-9-]*\/disks\/([a-zA-Z0-9-]*)\"/source = \"https:\/\/www.googleapis.com\/compute\/v1\/projects\/$$\{var.project}\/zones\/$$\{var.zone}\/disks\/\1\"/g" $${TF_FILE}; \
		gsed -i "/initialize_params {/,/^    }/d" $${TF_FILE}; \
		gsed -i "/reservation_affinity {/,/^  }/d" $${TF_FILE}; \
		hcledit attribute set resource.google_compute_instance.$${TF_VM_NAME}.machine_type \"f1-micro\" --file $${TF_FILE} --update; \
		hcledit attribute set resource.google_compute_instance.$${TF_VM_NAME}.service_account.email \"vm-migration-test@movsic-test.iam.gserviceaccount.com\" --file $${TF_FILE} --update; \
	done;

update_disks:
	TF_FILES=$$(find ./${TF_TARGET_PATH} -type f -name "*.tf" | grep ComputeDisk); \
	for TF_FILE in $${TF_FILES}; do \
		TF_DISK_NAME=$$(gsed -nE 's/resource "google_compute_disk" "([a-zA-Z0-9_]*)" \{/\1/pi' $${TF_FILE}); \
		echo TF_FILE: $${TF_FILE}; \
		echo TF_DISK_NAME: $${TF_DISK_NAME}; \
		hcledit attribute set resource.google_compute_disk.$${TF_DISK_NAME}.zone var.zone --file $${TF_FILE} --update; \
		hcledit attribute set resource.google_compute_disk.$${TF_DISK_NAME}.project var.project --file $${TF_FILE} --update; \
		hcledit attribute append resource.google_compute_disk.$${TF_DISK_NAME}.image \"https://www.googleapis.com/compute/beta/projects/debian-cloud/global/images/debian-11-bullseye-v20230509\" --file $${TF_FILE} --update; \
		hcledit attribute set resource.google_compute_disk.$${TF_DISK_NAME}.image \"https://www.googleapis.com/compute/beta/projects/debian-cloud/global/images/debian-11-bullseye-v20230509\" --file $${TF_FILE} --update; \
		hcledit attribute set resource.google_compute_disk.$${TF_DISK_NAME}.size 10 --file $${TF_FILE} --update; \
	done;

update_subnets:
	TF_FILES=$$(find ./${TF_TARGET_PATH} -type f -name "*.tf" | grep ComputeSubnetwork); \
	for TF_FILE in $${TF_FILES}; do \
		TF_SUBNET_NAME=$$(gsed -nE 's/resource "google_compute_subnetwork" "([a-zA-Z0-9_]*)" \{/\1/pi' $${TF_FILE}); \
		echo TF_FILE: $${TF_FILE}; \
		echo TF_SUBNET_NAME: $${TF_SUBNET_NAME}; \
		hcledit attribute set resource.google_compute_subnetwork.$${TF_SUBNET_NAME}.network \"https://www.googleapis.com/compute/v1/projects/$$\{var.project\}/global/networks/$$\{var.network\}\" --file $${TF_FILE} --update; \
		hcledit attribute set resource.google_compute_subnetwork.$${TF_SUBNET_NAME}.region var.region --file $${TF_FILE} --update; \
		hcledit attribute set resource.google_compute_subnetwork.$${TF_SUBNET_NAME}.project var.project --file $${TF_FILE} --update; \
	done;

create_snapshot:
	TF_FILES=$$(find ./${TF_TARGET_PATH} -type f -name "*.tf" | grep ComputeDisk); \
	for TF_FILE in $${TF_FILES}; do \
		TF_DISK_NAME=$$(gsed -nE 's/resource "google_compute_disk" "([a-zA-Z0-9_]*)" \{/\1/pi' $${TF_FILE}); \
		DISK_NAME=$$(hcledit attribute get resource.google_compute_disk.$${TF_DISK_NAME}.name --file $${TF_FILE} | tr -d '"'); \
		echo TF_DISK_NAME: $${TF_DISK_NAME}; \
		TF_SNAPSHOT_FILE=$${TF_FILE//ComputeDisk/ComputeSnapshot}; \
		echo TF_SNAPSHOT_FILE: $${TF_SNAPSHOT_FILE}; \
		TF_SNAPSHOT_PATH=$$(dirname $${TF_SNAPSHOT_FILE}); \
		if [ -z "$${TF_DISK_NAME}" ]; then \
			echo "Variable file -> skipping"; \
			continue; \
		fi; \
		mkdir -p $${TF_SNAPSHOT_PATH}; \
		echo "data \"google_compute_disk\" \"$${TF_DISK_NAME}\" {\n \
			name    = \"$${DISK_NAME}\"\n \
			project = var.source_project\n \
			zone = var.source_zone\n \
		}" > $${TF_SNAPSHOT_FILE}; \
		echo "resource \"google_compute_snapshot\" \"$${TF_DISK_NAME}_snapshot_init\" {\n \
			name = \"$${DISK_NAME}-snapshot\"\n \
			source_disk = data.google_compute_disk.$${TF_DISK_NAME}.id\n \
			zone = var.zone\n \
			project = var.project\n \
			storage_locations = [var.region]\n \
		}" >> $${TF_SNAPSHOT_FILE}; \
	done;

generate_tf_files:
	rm -rf ./${TF_TARGET_PATH}/main.tf;
	MODULE_PATHS=$$(find ${TF_TARGET_PATH} -type f -name "*.tf" | xargs -I% dirname % | sort -u); \
	for MODULE_FULL_PATH in $${MODULE_PATHS}; do \
		MODULE_PATH=$${MODULE_FULL_PATH//${TF_TARGET_PATH}\//}; \
		MODULE_NAME=$${MODULE_PATH//\//-}; \
		echo MODULE_PATH: $${MODULE_PATH}; \
		echo MODULE_NAME: $${MODULE_NAME}; \
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
			" > $${MODULE_FULL_PATH}/variables.tf; \
		MODULE_PATH_ARR=($${MODULE_PATH//\// }); \
		if [[ "$${MODULE_PATH}" == *"ComputeInstance"*  ]]; then \
			echo "module \"$${MODULE_NAME}\"{\n \
				source = \"./$${MODULE_PATH}\"\n \
				source_project=\"$${MODULE_PATH_ARR[0]}\"\n \
				source_region=\"$${MODULE_PATH_ARR[4]%-*}\"\n \
				source_zone=\"$${MODULE_PATH_ARR[4]}\"\n \
				source_network=\"$${MODULE_PATH_ARR[2]}\"\n \
				source_subnet=\"$${MODULE_PATH_ARR[3]}\"\n \
				project=\"${TARGET_PROJECT}\"\n \
				region=\"${TARGET_REGION}\"\n \
				zone=\"${TARGET_ZONE}\"\n \
				network=\"${TARGET_NETWORK}\"\n \
				subnet=\"${TARGET_SUBNET}\"\n \
			}" >> ./${TF_TARGET_PATH}/main.tf; \
			hcledit attribute append module.$${MODULE_PATH//\//-}.depends_on [module.$${MODULE_PATH_ARR[0]}-ComputeDisk-$${MODULE_PATH_ARR[2]}-$${MODULE_PATH_ARR[3]}-$${MODULE_PATH_ARR[4]},module.$${MODULE_PATH_ARR[0]}-ComputeSubnetwork-$${MODULE_PATH_ARR[2]}-$${MODULE_PATH_ARR[3]}-$${MODULE_PATH_ARR[4]}] --newline --file ./${TF_TARGET_PATH}/main.tf --update; \
		fi; \
		if [[ "$${MODULE_PATH}" == *"ComputeDisk"*  ]]; then \
			echo "module \"$${MODULE_NAME}\"{\n \
				source = \"./$${MODULE_PATH}\"\n \
				source_project=\"$${MODULE_PATH_ARR[0]}\"\n \
				source_region=\"$${MODULE_PATH_ARR[4]%-*}\"\n \
				source_zone=\"$${MODULE_PATH_ARR[4]}\"\n \
				source_network=\"$${MODULE_PATH_ARR[2]}\"\n \
				source_subnet=\"$${MODULE_PATH_ARR[3]}\"\n \
				project=\"${TARGET_PROJECT}\"\n \
				region=\"${TARGET_REGION}\"\n \
				zone=\"${TARGET_ZONE}\"\n \
			}" >> ./${TF_TARGET_PATH}/main.tf; \
			hcledit attribute append module.$${MODULE_PATH//\//-}.depends_on [module.$${MODULE_PATH_ARR[0]}-ComputeSnapshot-$${MODULE_PATH_ARR[2]}-$${MODULE_PATH_ARR[3]}-$${MODULE_PATH_ARR[4]}] --newline --file ./${TF_TARGET_PATH}/main.tf --update; \
		fi; \
		if [[ "$${MODULE_PATH}" == *"ComputeSnapshot"*  ]]; then \
			echo "module \"$${MODULE_NAME}\"{\n \
				source = \"./$${MODULE_PATH}\"\n \
				source_project=\"$${MODULE_PATH_ARR[0]}\"\n \
				source_region=\"$${MODULE_PATH_ARR[4]%-*}\"\n \
				source_zone=\"$${MODULE_PATH_ARR[4]}\"\n \
				source_network=\"$${MODULE_PATH_ARR[2]}\"\n \
				source_subnet=\"$${MODULE_PATH_ARR[3]}\"\n \
				project=\"${TARGET_PROJECT}\"\n \
				region=\"${TARGET_REGION}\"\n \
				zone=\"${TARGET_ZONE}\"\n \
			}" >> ./${TF_TARGET_PATH}/main.tf; \
		fi; \
		if [[ "$${MODULE_PATH}" == *"ComputeSubnetwork"*  ]]; then \
			echo "module \"$${MODULE_NAME}\"{\n \
				source = \"./$${MODULE_PATH}\"\n \
				source_project=\"$${MODULE_PATH_ARR[0]}\"\n \
				source_region=\"$${MODULE_PATH_ARR[4]%-*}\"\n \
				source_zone=\"$${MODULE_PATH_ARR[4]}\"\n \
				source_network=\"$${MODULE_PATH_ARR[2]}\"\n \
				source_subnet=\"$${MODULE_PATH_ARR[3]}\"\n \
				project=\"${TARGET_PROJECT}\"\n \
				region=\"${TARGET_REGION}\"\n \
				zone=\"${TARGET_ZONE}\"\n \
				network=\"${TARGET_NETWORK}\"\n \
			}" >> ./${TF_TARGET_PATH}/main.tf; \
		fi; \
	done;
	terraform fmt -recursive ${TF_TARGET_PATH}

add_snapshot:
	TIME_NOW=$$(date +'%Y_%m_%d_%H_%M_%S'); \
	TF_FILES=$$(find ./${TF_TARGET_PATH} -type f -name "*.tf" | grep ComputeSnapshot); \
	for TF_FILE in $${TF_FILES}; do \
		echo TF_FILE: $${TF_FILE}; \
		TF_FILE_NAME=$$(basename $${TF_FILE} .tf); \
		echo TF_FILE_NAME $${TF_FILE_NAME}; \
		TF_DISK_NAME=$$(gsed -nE 's/data "google_compute_disk" "([a-zA-Z0-9_]*)" \{/\1/pi' $${TF_FILE}); \
		echo TF_DISK_NAME $${TF_DISK_NAME}; \
		echo data.google_compute_disk.$${TF_DISK_NAME}.name; \
		DISK_NAME=$$(hcledit attribute get data.google_compute_disk.$${TF_DISK_NAME}.name --file $${TF_FILE} | tr -d '"'); \
		echo DISK_NAME $${DISK_NAME}; \
		if [ "$${TF_FILE_NAME}" = "variables" ]; then \
			echo "$${TF_FILE} file -> skipping"; \
			continue; \
		fi; \
		echo "resource \"google_compute_snapshot\" \"$${TF_DISK_NAME}_$${TIME_NOW}\" {\n \
			name = \"$${DISK_NAME}-snapshot-$${TIME_NOW//_/-}\"\n \
			source_disk = data.google_compute_disk.$${TF_DISK_NAME}.id\n \
			zone = var.zone\n \
			project = var.project\n \
			storage_locations = [var.region]\n \
		}" >> $${TF_FILE}; \
	done;

update_disk_source:
	TF_FILES=$$(find ./${TF_TARGET_PATH} -type f -name "*.tf" | grep ComputeDisk); \
	for TF_FILE in $${TF_FILES}; do \
		TF_FILE_NAME=$$(basename $${TF_FILE} .tf); \
		if [ "$${TF_FILE_NAME}" = "variables" ]; then \
			echo "$${TF_FILE} file -> skipping"; \
			continue; \
		fi; \
		TF_DISK_NAME=$$(gsed -nE 's/resource "google_compute_disk" "([a-zA-Z0-9_]*)" \{/\1/pi' $${TF_FILE}); \
		echo TF_DISK_NAME: $${TF_DISK_NAME}; \
		LAST_SNAPSHOT_TF_NAME=$$(gsed -nE 's/resource "google_compute_snapshot" "([a-zA-Z0-9_]*)" \{/\1/pi' $${TF_FILE//ComputeDisk/ComputeSnapshot} | tail -n1); \
		echo LAST_SNAPSHOT_TF_NAME $${LAST_SNAPSHOT_TF_NAME}; \
		LAST_SNAPSHOT_NAME=$$(hcledit attribute get resource.google_compute_snapshot.$${LAST_SNAPSHOT_TF_NAME}.name --file $${TF_FILE//ComputeDisk/ComputeSnapshot} | tr -d '"'); \
		echo LAST_SNAPSHOT_NAME $${LAST_SNAPSHOT_NAME}; \
		hcledit attribute append resource.google_compute_disk.$${TF_DISK_NAME}.snapshot \"https://www.googleapis.com/compute/v1/projects/$$\{var.project\}/global/snapshots/$${LAST_SNAPSHOT_NAME}\" --newline --file $${TF_FILE} --update; \
		hcledit attribute set resource.google_compute_disk.$${TF_DISK_NAME}.snapshot \"https://www.googleapis.com/compute/v1/projects/$$\{var.project\}/global/snapshots/$${LAST_SNAPSHOT_NAME}\" --file $${TF_FILE} --update; \
		hcledit attribute rm resource.google_compute_disk.$${TF_DISK_NAME}.image --file $${TF_FILE} --update; \
	done; \

stop_vms:
	TF_FILES=$$(find ./${TF_EXPORT_PATH} -type f -name "*.tf" | grep ComputeInstance); \
	for TF_FILE in $${TF_FILES}; do \
		TF_VM_NAME=$$(basename $${TF_FILE//-/_} .tf); \
		if [ "$${TF_VM_NAME}" = "variables" ]; then \
			echo "$${TF_FILE} file -> skipping"; \
			continue; \
		fi; \
		hcledit attribute append resource.google_compute_instance.$${TF_VM_NAME}.desired_status \"TERMINATED\" --newline --file $${TF_FILE} --update; \
		hcledit attribute set resource.google_compute_instance.$${TF_VM_NAME}.desired_status \"TERMINATED\" --file $${TF_FILE} --update; \
	done;
	#		hcledit attribute set resource.google_compute_instance.$${TF_VM_NAME}.boot_disk.auto_delete false --file $${TF_FILE} --update; \

start_vms:
	TF_FILES=$$(find ./${TF_EXPORT_PATH} -type f -name "*.tf" | grep ComputeInstance); \
	for TF_FILE in $${TF_FILES}; do \
		TF_VM_NAME=$$(basename $${TF_FILE//-/_} .tf); \
		if [ "$${TF_VM_NAME}" = "variables" ]; then \
			echo "$${TF_FILE} file -> skipping"; \
			continue; \
		fi; \
		echo TF_VM_NAME $${TF_VM_NAME}; \
		hcledit attribute append resource.google_compute_instance.$${TF_VM_NAME}.desired_status \"RUNNING\" --newline --file $${TF_FILE} --update; \
		hcledit attribute set resource.google_compute_instance.$${TF_VM_NAME}.desired_status \"RUNNING\" --file $${TF_FILE} --update; \
	done;

diff_vms:
	TF_FILES=$$(find ./${TF_TARGET_PATH} -type f -name "*.tf" | grep ComputeInstance); \
	for TF_FILE in $${TF_FILES}; do \
		echo TF_FILE $${TF_FILE}; \
		TF_VM_NAME=$$(basename $${TF_FILE//-/_} .tf); \
		if [ "$${TF_VM_NAME}" = "variables" ]; then \
			echo "$${TF_FILE} file -> skipping"; \
			continue; \
		fi; \
		echo TF_VM_NAME $${TF_VM_NAME}; \
		VM_NAME=$$(hcledit attribute get resource.google_compute_instance.$${TF_VM_NAME}.name --file $${TF_FILE} | tr -d '"'); \
		echo VM_NAME $${VM_NAME}; \
		TF_FILE_ARR=($${TF_FILE//\// }); \
		echo TF_FILE_ARR $${TF_FILE_ARR[@]}; \
		SOURCE=$$(hcledit attribute get module.projects-$${TF_FILE_ARR[3]}-ComputeInstance-$${TF_FILE_ARR[5]}-$${TF_FILE_ARR[6]}-$${TF_FILE_ARR[7]}.source -f ./${TF_TARGET_PATH}/main.tf | tr -d '"'); \
		TARGET_VM_ZONE=$$(hcledit attribute get module.projects-$${TF_FILE_ARR[3]}-ComputeInstance-$${TF_FILE_ARR[5]}-$${TF_FILE_ARR[6]}-$${TF_FILE_ARR[7]}.zone -f ./${TF_TARGET_PATH}/main.tf | tr -d '"'); \
		echo TARGET_VM_ZONE $${TARGET_VM_ZONE}; \
		TARGET_VM_PROJECT=$$(hcledit attribute get module.projects-$${TF_FILE_ARR[3]}-ComputeInstance-$${TF_FILE_ARR[5]}-$${TF_FILE_ARR[6]}-$${TF_FILE_ARR[7]}.project -f ./${TF_TARGET_PATH}/main.tf | tr -d '"'); \
		echo TARGET_VM_PROJECT $${TARGET_VM_PROJECT}; \
		if [ -n "$${SOURCE}" ]; then \
			diff <( gcloud compute instances describe $${VM_NAME} --zone=$${SOURCE_VM_ZONE} --project=${SOURCE_PROJECT} ) <( gcloud compute instances describe $${VM_NAME} --zone=$${TARGET_VM_ZONE} --project=$${TARGET_VM_PROJECT} ); \
		fi; \
	done; \

tf_target_apply:
	terraform -chdir=${TF_TARGET_PATH} init; \
	terraform -chdir=${TF_TARGET_PATH} apply -parallelism=500 -auto-approve; \

tf_source_import:
	terraform -chdir=${TF_EXPORT_PATH} init; \
	cd ${TF_EXPORT_PATH} && sh import.sh; \

tf_source_apply:
	terraform -chdir=${TF_EXPORT_PATH} init; \
	terraform -chdir=${TF_EXPORT_PATH} apply -parallelism=500 -auto-approve; \

tf_source_destroy:
	terraform -chdir=${TF_EXPORT_PATH} init; \
	terraform -chdir=${TF_EXPORT_PATH} destroy -parallelism=500 -auto-approve; \

clean:
	terraform destroy --auto-approve
	rm -rf ${TF_EXPORT_PATH}
	rm -rf ${TF_TARGET_PATH}
