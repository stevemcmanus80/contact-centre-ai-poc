import boto3

from botocore.exceptions import ClientError

from config import (
    AWS_REGION,
    BEDROCK_MODEL_ID,
)

from prompts import build_customer_prompt

bedrock = boto3.client(
    "bedrock-runtime",
    region_name=AWS_REGION
)

def generate_customer_response(customer, reference, request_type):

    if request_type == "case_status":

        task = (
            "Explain the customer's case status clearly and professionally."
        )

    elif request_type == "request_document":

        task = (
            "Confirm that a replacement document has been requested "
            "and explain the expected delivery time."
        )

    else:

        task = "Respond appropriately to the customer."


    prompt = build_customer_prompt(
        customer,
        reference,
        task
    )

    try:

        response = bedrock.converse(
            modelId=BEDROCK_MODEL_ID,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "text": prompt
                        }
                    ]
                }
            ],
            inferenceConfig={
                "maxTokens": 200,
                "temperature": 0.2
            }
        )

        message = response["output"]["message"]["content"][0]["text"]

        print(f"Bedrock response: {message}")

        return message

    except ClientError as e:

        print(f"Bedrock error: {e}")
        raise
