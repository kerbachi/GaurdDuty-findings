output "lambda_function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.lambda.arn
}

output "eventbrdige_arn" {
  description = "Event Bridge ARN"
  value       = aws_cloudwatch_event_rule.guardduty_trigger.arn
}