data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_dynamodb_table" "contact_centre_cases" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ReferenceNumber"

  attribute {
    name = "ReferenceNumber"
    type = "S"
  }
}

resource "aws_lambda_function" "lex_orchestrator" {

  function_name = var.lambda_function_name

  role    = "arn:aws:iam::533140817207:role/service-role/lex_orchestrator-role-cad9eis1"
  handler = "lambda_function.lambda_handler"
  runtime = "python3.12"

  filename         = "../lambda.zip"
  source_code_hash = filebase64sha256("../lambda.zip")

  timeout     = 3
  memory_size = 128

  environment {
    variables = {
      DYNAMODB_TABLE  = var.dynamodb_table_name
      BEDROCK_MODEL_ID = var.bedrock_model_id
    }
  }
}

resource "aws_iam_role" "lex_orchestrator" {
  name = "lex_orchestrator-role-cad9eis1"
  path = "/service-role/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "lambda.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_basic_execution" {
  name = "AWSLambdaBasicExecutionRole-5d8eefc3-1af0-453d-a460-fdbda07c5dbe"
  path = "/service-role/"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect   = "Allow"
        Action   = "logs:CreateLogGroup"
        Resource = "arn:aws:logs:eu-west-2:533140817207:*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:eu-west-2:533140817207:log-group:/aws/lambda/lex_orchestrator:*"
        ]
      }
    ]
  })
}

data "aws_iam_policy" "dynamodb_read_only" {
  arn = "arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "dynamodb_read_only" {
  role       = aws_iam_role.lex_orchestrator.name
  policy_arn = data.aws_iam_policy.dynamodb_read_only.arn
}

resource "aws_iam_role_policy" "bedrock_invoke_model" {
  name = "BedrockInvokeModelPolicy"
  role = aws_iam_role.lex_orchestrator.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect   = "Allow"
        Action   = "bedrock:InvokeModel"
        Resource = "*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "lex_orchestrator" {
  name = "/aws/lambda/lex_orchestrator"
}