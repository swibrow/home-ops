################################################################################
# Lambda Layer (urllib3)
################################################################################

resource "null_resource" "lambda_layer" {
  provisioner "local-exec" {
    command = "pip install urllib3 -t ${path.module}/.build/layer/python --upgrade --quiet"
  }

  triggers = {
    always_run = timestamp()
  }
}

data "archive_file" "layer" {
  type        = "zip"
  source_dir  = "${path.module}/.build/layer"
  output_path = "${path.module}/.build/layer.zip"

  depends_on = [null_resource.lambda_layer]
}

resource "aws_lambda_layer_version" "urllib3" {
  layer_name          = "${local.name}-urllib3"
  filename            = data.archive_file.layer.output_path
  source_code_hash    = data.archive_file.layer.output_base64sha256
  compatible_runtimes = ["python3.13"]
}

################################################################################
# Lambda Function
################################################################################

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/.build/lambda.zip"
}

resource "aws_lambda_function" "alexa" {
  function_name    = local.name
  description      = "Alexa Smart Home skill handler for Home Assistant"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.13"
  timeout          = 15
  memory_size      = 128

  role = aws_iam_role.lambda.arn

  layers = [aws_lambda_layer_version.urllib3.arn]

  environment {
    variables = {
      BASE_URL = var.home_assistant_url
      DEBUG    = var.debug ? "1" : ""
    }
  }

  tags = local.tags
}

################################################################################
# IAM Role
################################################################################

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

################################################################################
# Alexa Smart Home Trigger
################################################################################

resource "aws_lambda_permission" "alexa" {
  statement_id       = "AllowAlexaSmartHome"
  action             = "lambda:InvokeFunction"
  function_name      = aws_lambda_function.alexa.function_name
  principal          = "alexa-connectedhome.amazon.com"
  event_source_token = var.alexa_skill_id
}
