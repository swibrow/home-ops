output "lambda_function_arn" {
  description = "ARN of the Alexa Lambda function (use this in the Alexa Developer Console)"
  value       = aws_lambda_function.alexa.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.alexa.function_name
}
