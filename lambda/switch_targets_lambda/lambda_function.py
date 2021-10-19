# Import the SDK and required libraries
import boto3
import json
import os
import sys
import logging
from botocore.exceptions import ClientError

logger = logging.getLogger()
logging.basicConfig(level=logging.INFO)
logger.setLevel(logging.INFO)

#tg_arn = os.environ['TARGETGROUP_ARN'].strip()
elb_name = os.environ['ELB_NAME']
tg_name = os.environ['TG_NAME']

def lambda_handler(event, context):
    """
    Main Lambda handler
    """
#    print("Received event: " + json.dumps(event, indent=2))
    message = event['Records'][0]['Sns']['Message']
#    global sns_client
    global elbv2_client
#    global elbv2_client
    global ec2

#    try:
#        sns_client = boto3.client('sns')
#    except ClientError as e:
#        logger.error(e.response['Error']['Message'])

#    try:
#        elb_client = boto3.client('elb')
#    except ClientError as e:
#        logger.error(e.response['Error']['Message'])

    try:
        elbv2_client = boto3.client('elbv2')
    except ClientError as e:
        logger.error(e.response['Error']['Message'])

    try:
        ec2 = boto3.resource('ec2')
    except ClientError as e:
        logger.error(e.response['Error']['Message'])

    if "AlarmName" in message:
        json_message = json.loads(message)
        print("Message: " + json.dumps(json_message))
        accountid = str(json_message['AWSAccountId'])
        alarm_trigger = str(json_message['NewStateValue'])
        timestamp = str(json_message['StateChangeTime'])
        region = os.environ["AWS_REGION"]
        logger.info("=======Start Lambda Function=======")
        logger.info("AccountID:{}".format(accountid))
        logger.info("Region:{}".format(region))
        logger.info("Alarm State:{}".format(alarm_trigger))
        for entity in json_message['Trigger']['Dimensions']:
            if entity['name'] == "LoadBalancer":
                if str(entity['value']).split('/')[1] != elb_name:
                    loggger.warning("Loadbalancer {} not matching {}".format(entity['value'], elb_name))
                    return
        # Take actions when an Alarm is triggered
        if alarm_trigger == 'ALARM':
            target_instances = describe_targets_states(elb_name, tg_name)
            print(target_instances)
            switch_running_targets(target_instances)

def switch_running_targets(instances):
    """
    Shutdown unhealty but running instance, then start stopped instance
    """
    logger.info("\n==switch targets==\n unhealthy_list {}\n".format(instances))
    # find instance to stop
    to_stop_id = None
    to_stop_how = None
    to_start_id = None
    for instance_data in instances:
        if instance_data['TargetState'] == 'healthy':
            logger.warning("switching instances: healthy target found: {}, nothing to do?".format(instance_data['InstanceId']))
            return
        elif instance_data['InstanceState'] == 'stopped' and instance_data['TargetState'] == 'unused':
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
        logger.info("Stopping {}".format(to_stop_id))
        try:
            instance_obj = ec2.Instance(to_stop_id)
        except ClientError as e:
            logger.error(e.response['Error']['Message'])
        if to_stop_how == 'stop':
            try:
                instance_obj.stop()
                instance_obj.wait_until_stopped()
            except ClientError as e:
                logger.error(e.response['Error']['Message'])
        elif to_stop_how == 'wait-stop':
            try:
                instance_obj.wait_until_stopped()
            except ClientError as e:
                logger.error(e.response['Error']['Message'])
        elif to_stop_how == 'nop':
            pass
        elif to_stop_how == 'wait-settle':
            logger.error("{} instance state pending, what to do?".format(to_stop_id))
    if to_start_id != None:
        logger.info("Starting {}".format(to_start_id))
        try:
            instance_obj = ec2.Instance(to_start_id)
            instance_obj.start()
        except ClientError as e:
            logger.error(e.response['Error']['Message'])
    return

def describe_targets_states(elb_name, tg_name):
    """
    Describe targets health of ApplicationLoadBalancer
    """
    try:
        albs = elbv2_client.describe_load_balancers(Names=[elb_name])
    except ClientError as e:
        logger.error(e.response['Error']['Message'])
        return []
    elb_arn =  albs['LoadBalancers'][0]['LoadBalancerArn']
    try:
        tgs = elbv2_client.describe_target_groups(LoadBalancerArn=elb_arn)
    except ClientError as e:
        logger.error(e.response['Error']['Message'])
        return []
    for tg in tgs['TargetGroups']:
        if tg['TargetGroupName'] == tg_name:
            tg_arn = tg['TargetGroupArn']
            break
    target_list = []
    try:
        response = elbv2_client.describe_target_health(TargetGroupArn=tg_arn)
    except ClientError as e:
        logger.error(e.response['Error']['Message'])
        return []
    for item in response['TargetHealthDescriptions']:
        instance_id =  item['Target']['Id']
        try:
            instance = ec2.Instance(instance_id)
        except ClientError as e:
            logger.error(e.response['Error']['Message'])
            return []
        target_list.append({ 'InstanceId': instance_id, 'TargetState': item['TargetHealth']['State'], 'InstanceState': instance.state['Name'] })
    logger.info("elb - targets: {}".format(target_list))
    return target_list

#--- main (for testing) ---

#event = {
#    "Records": [
#      {
#        "EventVersion": "1.0",
#        "EventSubscriptionArn": "arn:aws:sns:us-east-2:123456789012:sns-lambda:21be56ed-a058-49f5-8c98-aedd2564c486",
#        "EventSource": "aws:sns",
#        "Sns": {
#          "SignatureVersion": "1",
#          "Timestamp": "2019-01-02T12:45:07.000Z",
#          "Signature": "tcc6faL2yUC6dgZdmrwh1Y4cGa/ebXEkAi6RibDsvpi+tE/1+82j...65r==",
#          "SigningCertUrl": "https://sns.us-east-2.amazonaws.com/SimpleNotificationService-ac565b8b1a6c5d002d285f9598aa1d9b.pem",
#          "MessageId": "95df01b4-ee98-5cb9-9903-4c221d41eb5e",
#          "Message": """
#              {
#                  "AlarmName": "test-alarm",
#                  "AWSAccountId": "123456789012",
#                  "NewStateValue": "ALARM",
#                  "StateChangeTime": "2020-12-04T03:57:01.659+0000",
#                  "Trigger": {
#                      "Dimensions": [
#                          { "name": "LoadBalancer", "value": "nexus-lb" }
#                      ]
#                   }
#              }
#          """ ,
#          "MessageAttributes": {
#            "Test": {
#              "Type": "String",
#              "Value": "TestString"
#            },
#            "TestBinary": {
#              "Type": "Binary",
#              "Value": "TestBinary"
#            }
#          },
#          "Type": "Notification",
#          "UnsubscribeUrl": "https://sns.us-east-2.amazonaws.com/?Action=Unsubscribe&amp;SubscriptionArn=arn:aws:sns:us-east-2:123456789012:test-lambda:21be56ed-a058-49f5-8c98-aedd2564c486",
#          "TopicArn":"arn:aws:sns:us-east-2:123456789012:sns-lambda",
#          "Subject": "TestInvoke"
#        }
#      }
#    ]
#  }
#
#context = ""
#
#lambda_handler(event, context)
