provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

locals {
    account_id = data.aws_caller_identity.current.account_id
}


# EventBridge was formerly known as CloudWatch Events. The functionality is identical.
resource "aws_cloudwatch_event_rule" "guardduty_trigger" {
  name        = "capture-guardduty-events"
  description = "Capture guardduty-events"
  event_bus_name = "default"
  state = "ENABLED"
  event_pattern = jsonencode({
                "source" : ["aws.guardduty"],
                "detail-type" : ["GuardDuty Finding"]   
                "detail" : { 
                  "type": [
                    "Recon:EC2/PortProbeUnprotectedPort",
                    "Recon:EC2/Portscan",
                    "UnauthorizedAccess:EC2/SSHBruteForce",
                    "UnauthorizedAccess:EC2/RDPBruteForce",
                    "Trojan:EC2/BlackholeTraffic",
                    "Trojan:EC2/DropPoint",
                    "UnauthorizedAccess:EC2/TorClient",
                    "UnauthorizedAccess:EC2/TorRelay"
                  ]
                }   
  })
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.guardduty_trigger.name
  target_id = "EventBridgeTrigger"
  arn       = aws_lambda_function.lambda.arn
}


resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda.arn
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_trigger.arn
}

# DynamoDB
resource "aws_dynamodb_table" "basic-dynamodb-table" {
  name           = var.dynamodb_table_name
  billing_mode   = "PROVISIONED"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "id"
  server_side_encryption {
    enabled = true
  }
  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name        = "GuarDuty-table"
    Environment = "dev"
  }
}


# SNS
resource "aws_sns_topic" "guardduty_findings_updates" {
  name = "GuardDuty-findings-updates-topic"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "user_updates_sqs_target" {
  topic_arn = aws_sns_topic.guardduty_findings_updates.arn
  protocol  = "email"
  endpoint  = var.sns_email_target
}