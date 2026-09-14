variable "aws_region" {
  type        = string
  description = "AWS Region"
}

variable "project_name" {
  type        = string
  description = "Project name"
}

variable "dynamodb_table_name" {
  type        = string
  description = "DynamoDB table name"
}

variable "lambda_function_name" {
  type        = string
  description = "Lambda function name"
}

variable "bedrock_model_id" {
  type        = string
  description = "Bedrock model identifier"
}