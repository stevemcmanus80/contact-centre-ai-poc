import os

AWS_REGION = os.environ.get("AWS_REGION", "eu-west-2")

DYNAMODB_TABLE = os.environ["DYNAMODB_TABLE"]

BEDROCK_MODEL_ID = os.environ["BEDROCK_MODEL_ID"]