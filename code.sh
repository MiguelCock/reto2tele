CLUSTER_REGION=us-east-1
CLUSTER_NAME=drupal
EFS_SECURITY_GROUP_NAME=drupal-vpc
EFS_FILE_SYSTEM_NAME=drupal

create_efs_mount_targets() {
    file_system_id=$(aws efs describe-file-systems \
                            --region $CLUSTER_REGION \
                            --query "FileSystems[?Name=='$EFS_FILE_SYSTEM_NAME'].FileSystemId" \
                            --output text) \
    && security_group_id=$(aws ec2 describe-security-groups \
    --region $CLUSTER_REGION \
    --query 'SecurityGroups[*]' \
    --output json \
    | jq -r 'map(select(.GroupName=="'$EFS_SECURITY_GROUP_NAME'")) | .[].GroupId') \
    && public_cluster_subnets=$(aws ec2 describe-subnets \
                --region $CLUSTER_REGION \
                --output json \
                --filters Name=tag:alpha.eksctl.io/cluster-name,Values=$CLUSTER_NAME Name=tag:aws:cloudformation:logical-id,Values=SubnetPublic* \
                | jq -r '.Subnets[].SubnetId')
    if [[ $? != 0 ]]; then
        exit 1
    fi
    for subnet in ${public_cluster_subnets[@]}
    do
        echo "Attempting to create mount target in "$subnet"..."

        aws efs create-mount-target \
            --file-system-id $file_system_id \
            --subnet-id $subnet \
            --security-groups $security_group_id \
        &> /dev/null \
        && echo "Mount target created!"
    done
}

create_efs_mount_targets