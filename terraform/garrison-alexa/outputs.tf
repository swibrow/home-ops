output "lambda_function_arn" {
  description = "ARN of the crier Lambda (the skill's default endpoint in the Alexa Developer Console)"
  value       = aws_lambda_function.crier.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.crier.function_name
}

output "crier_token" {
  description = "Bearer the Lambda presents to the crier; store it as Infisical /garrison/CRIER_TOKEN"
  value       = random_password.crier_token.result
  sensitive   = true
}
