# Import the SDK and required libraries
import boto3
import json
import os
import logging
from botocore.exceptions import ClientError

#logger = logging.getLogger()
#logger.setLevel(logging.INFO)



# Configure the SNS topic which you want to use for sending notifications
#namespace = os.environ['NAMESPACE']
#ondemand_healthcheck_flag = os.environ['ONDEMAND_HEALTHCHECK']
#sns_arn = os.environ['SNS_TOPIC']

elb_name = os.environ['ELB_NAME'].strip()

def test_lambda_handler():
    """
    Main Lambda handler
    """
    global elb_client
    global ec2_client

    try:
        elb_client = boto3.client('elb')
    except ClientError as e:
        print(e.response['Error']['Message'])

    try:
        ec2_client = boto3.client('ec2')
    except ClientError as e:
        print(e.response['Error']['Message'])
    target_instances = describe_targets_states(elb_name)
    switch_running_targets(target_instances, elb_name)

def switch_running_targets(instances, elb_name):
    """
    Shutdown unhealty but running instance, then start stopped instance
    """
    print("\n==switch targets==\n unhealthy_list {}\n".format(instances))
    # find instance to stop
    to_stop_id = None
    to_stop_how = None
    to_start_id = None
    for instance_data in instances:
        if instance_data['TargetState'] == 'InService':
            print("switching instances: InService target found: {}, nothing to do?".format(instance_data['InstanceId']))
            return
        elif instance_data['InstanceState'] == 'stopped':
            to_start_id = instance_data['InstanceId']
        else:
            to_stop_id = instance_data['InstanceId']
            instance_state = instance_data['InstanceState']
            if instance_state == 'running':
                to_stop_how = 'stop'
            elif instance_state in ['shutting-down', 'stopping']:
                to_stop_how = 'wait-stop'
            elif instance_state == 'terminated':
                to_stop_how = 'nop'
            elif instance_state == 'pending':
                to_stop_how = 'wait-settle'
            else:
                logger.error("Invalid {} instance state: {}".format(to_stop_id, instance_state))
    if to_stop_id != None and to_stop_how != None:
        try:
            instance_obj = ec2_client.Instance(to_stop_id)
        except ClientError as e:
            print(e.response['Error']['Message'])
        if to_stop_how == 'stop':
            try:
                instance_obj.stop()
                instance_obj.wait_until_stopped()
            except ClientError as e:
                print(e.response['Error']['Message'])
        elif to_stop_how == 'wait-stop':
            try:
                instance_obj.wait_until_stopped()
            except ClientError as e:
                print(e.response['Error']['Message'])
        elif to_stop_how == 'nop':
            pass
        elif to_stop_how == 'wait-settle':
            print("{} instance state pending, what to do?".format(to_stop_id))
    if to_start_id != None:
        try:
            instance_obj = ec2_client.Instance(to_start_id)
            instance_obj.start()
        except ClientError as e:
            print(e.response['Error']['Message'])
    return

def describe_targets_states(elb_name):
    """
    Describe targets health of Application/NetworkLoadBalancer
    """
    target_list = []
    try:
        response = elb_client.describe_instance_health(LoadBalancerName=elb_name)
    except ClientError as e:
        print(e.response['Error']['Message'])
        return []
    for item in response['Instances']:
        instance_id =  item['InstanceId']
        try:
            instance = ec2_client.Instance(instance_id)
        except ClientError as e:
            print(e.response['Error']['Message'])
            return []
        target_list.append({ 'InstanceId': item['InstanceId'], 'TargetState': item['State'], 'InstanceState': instance['State']['Name'] })
    print("elb {} - targets: {}".format(elb_name, target_list))
    return target_list

#==== main ====
test_lambda_handler()

