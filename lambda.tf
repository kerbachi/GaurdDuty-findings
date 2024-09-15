
# Option1 use local-exec to build the zip, but depends on does not work
# resource "null_resource" "python_packages_builder" {
# 	  triggers = {
# 	    updated_at = timestamp()
# 	  }
	

# 	  provisioner "local-exec" {
# 	    command = <<EOF
#       exit 1
#       CFLAGS='-march=x86-64' pip install atlassian-python-api -t "python"
#       /usr/bin/zip -r packages.zip python
# 	    EOF
	
#       interpreter = [ "/bin/sh", "-c" ]
# 	    working_dir = "${path.module}/${var.lambda_code_location}"
# 	  }
# }


# Option 2 upload packages.zip to S3, without building it in TF


data "archive_file" "lambda_zip" {
    type          = "zip"
    source_file   = "lambda_function.py"
    output_path   = "lambda_function.zip"
}


# Create Layer for Python requests
resource "aws_lambda_layer_version" "python_requests_layer" {
  filename   = "lambda_code/packages.zip"
  layer_name = "python_packages_layer"
  source_code_hash    = "${filebase64sha256("lambda_code/packages.zip")}"
  compatible_runtimes = ["python3.10"]

  # depends_on = [ null_resource.python_packages_builder ]
}





resource "aws_lambda_function" "lambda" {
  function_name   = var.lambda_name
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  layers = [aws_lambda_layer_version.python_requests_layer.arn]
  runtime = "python3.10"
  handler = "lambda_function.lambda_handler"
  role    = aws_iam_role.iam_for_lambda.arn
  timeout = 30
  environment {
    variables = {
      TABLE_NAME = var.dynamodb_table_name,
      JIRA_USERNAME = var.jira_username,
      JIRA_PASSWORD = var.jira_password,
      JIRA_URL = var.jira_url,
      JIRA_PROJECT_KEY = var.jira_project_key,
      JIRA_ISSUE_TYPE = var.jira_issue_type,
      SNS_TOPIC = aws_sns_topic.guardduty_findings_updates.arn
    }
  }
}
data "aws_iam_policy_document" "policy" {
   statement {
    sid    = ""
    effect = "Allow"
    principals {
      identifiers = ["lambda.amazonaws.com"]
      type        = "Service"
    }
    actions = ["sts:AssumeRole"]
   }
  
}

resource "aws_iam_role" "iam_for_lambda" {
  name               = "iam_for_lambda"
  assume_role_policy = data.aws_iam_policy_document.policy.json

  inline_policy {
    name = "Lambda_Permissions"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action   = ["dynamodb:*"]
          Effect   = "Allow"
          Resource = aws_dynamodb_table.basic-dynamodb-table.arn
        },
        {
            Action = ["logs:CreateLogGroup"]
            Effect = "Allow"
            Resource= "arn:aws:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/${var.lambda_name}"
        },
        {
            Action = [
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ]
            Effect = "Allow"
            Resource = [
                "arn:aws:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/${var.lambda_name}*"
            ]
        },
        {
            Action = [
                "ec2:*"
            ]
            Effect = "Allow"
            Resource = [ "arn:aws:ec2:${var.region}:${local.account_id}:instance/*" ]
        },
        {
            Action = [
                "ec2:DescribeInstances",
                "ec2:DescribeSecurityGroups",
                "ec2:CreateSecurityGroup"
            ]
            Effect = "Allow"
            Resource = [ "*" ]
        },
        {
            Action = [
                "ec2:ModifyNetworkInterfaceAttribute",
                "ec2:RevokeSecurityGroupEgress",
                "ec2:RevokeSecurityGroupIngress",
                "ec2:AuthorizeSecurityGroupIngress"
            ]
            Effect = "Allow"
            Resource = [ 
              "arn:aws:ec2:${var.region}:${local.account_id}:network-interface/*",
              "arn:aws:ec2:${var.region}:${local.account_id}:security-group/*" ]
        },
        {
            Action = [
                "SNS:Publish"
            ]
            Effect = "Allow"
            Resource = [ aws_sns_topic.guardduty_findings_updates.arn ]
        }
      ]
    })
  }
}

