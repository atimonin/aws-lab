#!/bin/sh

source nexus_ids

# find snapshot
SNAP_ID=$(aws ec2 describe-images --owners self --image-ids ${NEXUS_AMI_ID} | \
	jq -r '.Images[]|.BlockDeviceMappings[]| select(.Ebs)| .Ebs.SnapshotId')

aws ec2 deregister-image --image-id ${NEXUS_AMI_ID}
aws ec2 delete-snapshot --snapshot-id ${SNAP_ID}
aws efs delete-file-system --file-system-id ${NEXUS_EFS_ID}

