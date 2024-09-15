variable "region" {
    description = "AWS Region"
    default = "us-east-1"
}

variable "lambda_name" {
    description = "AWS Region"
    default = "lambda-guardduty"
}

variable "lambda_code_location" {
    description = "Lambda code location"
    default = "lambda_code"
}

variable "dynamodb_table_name" {
    description = "DyanmoDB table name"
    default = "GuradDutyFindings"
}

variable "sns_email_target" {
    description = "Email target for SNS subscription"
    default = "test@acme.com"
}

variable "jira_username" {
    description = "Username for JIRA API call"
    default = "test@acme.com"
}

variable "jira_password" {
    description = "Password for JIRA API call"
    default = "****"
}

variable "jira_url" {
    description = "URL for JIRA API call"
    default = "https://test.atlassian.net"
}

variable "jira_project_key" {
    description = "Project Key for JIRA API call"
    default = "SUP"
}

variable "jira_issue_type" {
    description = "Issue type for JIRA API call"
    default = "Task"
}
