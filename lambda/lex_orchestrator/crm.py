import boto3

from config import (
    AWS_REGION,
    DYNAMODB_TABLE
)

dynamodb = boto3.resource(
    "dynamodb",
    region_name=AWS_REGION
)

table = dynamodb.Table(
    DYNAMODB_TABLE
)


def get_customer(reference):

    response = table.get_item(
        Key={
            "ReferenceNumber": reference
        }
    )

    return response.get("Item")