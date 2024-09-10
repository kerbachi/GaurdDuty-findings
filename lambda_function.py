import json
import os
import logging
import boto3
from atlassian import Jira




dynamodb_resource = boto3.resource("dynamodb")
ec2 = boto3.client('ec2')
ec2r = boto3.resource('ec2')
sns = boto3.client('sns')
logger = logging.getLogger()
logger.setLevel(logging.INFO)
logger.info('Loading function')

############################
# Variables
############################

table_name = os.environ['TABLE_NAME']

jira_username = os.environ['JIRA_USERNAME']
jira_password = os.environ['JIRA_PASSWORD']
jira_url = os.environ['JIRA_URL']
jira_project_key = os.environ['JIRA_PROJECT_KEY']
jira_issue_type = os.environ['JIRA_ISSUE_TYPE']

sns_topic = os.environ['SNS_TOPIC']


############################
# Auxilaty Functions
############################

def put_item_in_dynamodb(table, event):
    """
    Insert finding in DynamoDB table after verify that
      it doesn't exist already.

    Args:
        table (str): DynamoDB table.
        event (dict): Event as received from EventBridge.

    Returns:
        None.
    """
    try:
        table = dynamodb_resource.Table(table)
        # Check if an item with the same id already exists
        id_value = event["detail"]["id"]
        response = table.get_item(Key={"id": id_value})
        if "Item" in response:
            logger.debug(f"Item with id {id_value} already exists in the table.")
        else:
            logger.debug(f"Item with id {id_value} does not exist in the table.")
            # Insert the item into the DynamoDB table
            response = table.put_item(
                Item={
                    "id": event["detail"]["id"],
                    "detail-type": event["detail-type"],
                    "type": event["detail"]["type"],
                    "source": event["source"],
                    "accountId": event["detail"]["accountId"],
                    "region": event["detail"]["region"],
                    "time": event["time"],
                }
            )
            logger.info("Response from DynamoDB:" + json.dumps(response, indent=2))

    except Exception as e:
        print("Error adding item to DynamoDB table:", e)
        raise e


# Update SG of the instance to be isolated
def update_sg_of_instance(instance_id, vpc_id):
    """
    Update SecurityGroup of a host EC2.
    Connections must be converted into nontracked by applying 0.0.0.0/0 rule.

    Args:
        instance_id (str): EC2 instance ID.
        vpc_id (str): VPC ID.

    Returns:
        None.
    """
    logger.info(f"Updating SG for instance {instance_id}")
    isolation_sg_name = "ISOLATION-SG-" + instance_id
    isolation_sg_id = ""
    instance_network_details = {}
    instance_oringin_sgs = []
    try:
        # Find all SGs
        instance = ec2.describe_instances(InstanceIds=[instance_id])
        for interfaces in instance["Reservations"][0]["Instances"][0]["NetworkInterfaces"]:
            instance_network_details[interfaces['NetworkInterfaceId']] = interfaces["Groups"]
            for group in interfaces["Groups"]:
                instance_oringin_sgs.append(group["GroupId"])
        logger.debug(f"instance_network_details: {instance_network_details}")


        # Create Isolation SG if doesn't exist
        sg = ""
        all_sgs = []
        does_sg_exist_response = ec2.describe_security_groups()
        for sgroup in does_sg_exist_response['SecurityGroups']:
            all_sgs.append(sgroup['GroupName'])
            if sgroup['GroupName'] == isolation_sg_name:
                sg = ec2r.SecurityGroup(sgroup['GroupId'])
                isolation_sg_id = sgroup['GroupId']

        if isolation_sg_name not in all_sgs:
            logger.info(f"Security Group {isolation_sg_name} does not exist in vpc {vpc_id}.")
            sg_create = ec2.create_security_group(GroupName=isolation_sg_name,
                                                Description='SG to Isolate an instance',
                                                VpcId=vpc_id)
            isolation_sg_id = sg_create['GroupId']
            data = ec2.authorize_security_group_ingress(
                    GroupId=isolation_sg_id,
                    IpPermissions=[
                    {   'IpProtocol': '-1',
                        'IpRanges': [{'CidrIp': '0.0.0.0/0'}]}
                    ])
            logger.info(f'Isolation SG Successfully created {data}')
            sg = ec2r.SecurityGroup(isolation_sg_id)

        # Replace all SGs with the isolation SG
        for interface in instance_network_details:
            ec2.modify_network_interface_attribute(
                NetworkInterfaceId=interface,
                Groups=[isolation_sg_id]
            )


        # Remove all rules from the isolation SG
        data = sg.revoke_ingress(
                IpPermissions=sg.ip_permissions
        )
        data = sg.revoke_egress(
                IpPermissions=sg.ip_permissions_egress
        )

    except Exception as e:
        print("Error updating SG of instance:", e)
        raise e


def open_jira_issue(finding_type, instance_id):
    """
    Open a Jira Ticket using API call.

    Args:
        finding_type (str): GuardDuty finding Type.
        instance_id (str): EC2 instance ID.

    Returns:
        None.
    """
    logger.info("Opening Jira issue for finding {}, with instance {}".
                format(finding_type, instance_id))
    issue_summary= f"GuarDuty alert for {finding_type} with instance {instance_id}"
    try:
        # Create a Jira client
        jira = Jira(url = jira_url,
            username = jira_username,
            password = jira_password,
            cloud=True)

        # Create a new issue
        fields = {
            "summary": issue_summary,
            "project": {"key": jira_project_key},
            "issuetype": {"name": jira_issue_type}
        }
        response=jira.issue_create(fields=fields)
        logger.info("response from Jira API call:" + json.dumps(response))

    except Exception as e:
        print("Error opening Jira issue:", e)
        raise e


def send_sns_message(message):
    """
    Send SNS Email containing the EC2 instance id and GuardDuty finding type.

    Args:
        message (str): Message to send by AWS SNS.

    Returns:
        None.
    """
    try:
        # Publish a message to the specified SNS topic
        response = sns.publish(
            TopicArn=sns_topic,
            Message=message,
            Subject="GuarDuty Alert",
        )
        logger.info("response from SNS API call:" + json.dumps(response))

    except Exception as e:
        print("Error sending SNS message:", e)
        raise e

############################
# Handler function
############################

def lambda_handler(event, context):

    logger.info("Received event: " + json.dumps(event))
    logger.info("Received Context: " + str(context))

    put_item_in_dynamodb(table_name, event)

    update_sg_of_instance(event["detail"]["resource"]["instanceDetails"]["instanceId"],
                          event["detail"]["resource"]["instanceDetails"]["networkInterfaces"][0]["vpcId"])

    open_jira_issue(event["detail"]["type"],
                    event["detail"]["resource"]["instanceDetails"]["instanceId"])

    send_sns_message("GuarDuty Alert for finding {} with instance {}".
                     format(event["detail"]["type"],
                            event["detail"]["resource"]["instanceDetails"]["instanceId"]))
