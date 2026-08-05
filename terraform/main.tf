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