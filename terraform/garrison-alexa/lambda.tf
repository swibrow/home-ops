data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/.build/lambda.zip"
}

resource "aws_lambda_function" "crier" {
  function_name    = local.name
  description      = "Alexa Custom Skill proxy for the garrison crier (handler from swibrow/garrison deploy/alexa)"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.13"
  timeout          = 10
  memory_size      = 128

  role = aws_iam_role.lambda.arn

  environment {
    variables = {
      CRIER_URL   = var.crier_url
      CRIER_TOKEN = random_password.crier_token.result
      DEBUG       = var.debug ? "1" : ""
    }
  }

  tags = local.tags
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.name}-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom skills invoke through alexa-appkit (Smart Home skills use
# alexa-connectedhome); the token pins invocation to this one skill.
resource "aws_lambda_permission" "alexa" {
  statement_id       = "AllowAlexaSkillsKit"
  action             = "lambda:InvokeFunction"
  function_name      = aws_lambda_function.crier.function_name
  principal          = "alexa-appkit.amazon.com"
  event_source_token = var.alexa_skill_id
}
