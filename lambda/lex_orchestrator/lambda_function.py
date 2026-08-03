import json
import boto3
from botocore.exceptions import ClientError

# ---------------------------------------------------------------------
# AWS clients
# ---------------------------------------------------------------------

dynamodb = boto3.resource("dynamodb", region_name="eu-west-2")
table = dynamodb.Table("ContactCentreCases")

bedrock = boto3.client("bedrock-runtime", region_name="eu-west-2")

MODEL_ID = "global.amazon.nova-2-lite-v1:0"


# ---------------------------------------------------------------------
# DynamoDB
# ---------------------------------------------------------------------

def get_customer(reference):

    try:
        response = table.get_item(
            Key={
                "ReferenceNumber": reference
            }
        )

        return response.get("Item")

    except ClientError as e:
        print(f"DynamoDB error: {e}")
        raise


# ---------------------------------------------------------------------
# Bedrock
# ---------------------------------------------------------------------

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


    prompt = f"""
You are a professional customer service assistant.

Generate a concise, friendly response for the customer.

Use ONLY the information provided below.
Do not invent facts, dates, actions or outcomes.

Customer information:
Name: {customer['Name']}
Benefit: {customer['Benefit']}
Case status: {customer['Status']}
Last update: {customer['LastUpdate']}
Reference number: {reference}

Task:
{task}

Keep the response suitable for a contact centre conversation.
Do not mention that you are an AI.
"""

    try:

        response = bedrock.converse(
            modelId=MODEL_ID,
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


# ---------------------------------------------------------------------
# Business Functions
# ---------------------------------------------------------------------

def check_case_status(reference):

    customer = get_customer(reference)

    if not customer:

        return (
            f"Sorry, I couldn't find a case for reference {reference}."
        )

    return generate_customer_response(
        customer,
        reference,
        "case_status"
    )


def request_document(reference):

    customer = get_customer(reference)

    if not customer:

        return (
            f"Sorry, I couldn't find a case for reference {reference}."
        )

    return generate_customer_response(
        customer,
        reference,
        "request_document"
    )


def speak_to_adviser():

    return (
        "Certainly. I'll connect you to one of our advisers now."
    )


# ---------------------------------------------------------------------
# Lambda Entry Point
# ---------------------------------------------------------------------

def lambda_handler(event, context):

    print("Incoming Event:")
    print(json.dumps(event, indent=2))

    intent = event["sessionState"]["intent"]["name"]

    slots = event["sessionState"]["intent"].get("slots", {})

    # -------------------------------------------------------------
    # Extract and normalise reference number
    # -------------------------------------------------------------

    reference = "UNKNOWN"

    if (
        slots.get("ReferenceNumber")
        and slots["ReferenceNumber"].get("value")
        and slots["ReferenceNumber"]["value"].get("interpretedValue")
    ):
        reference = (
            slots["ReferenceNumber"]["value"]["interpretedValue"]
            .strip()
            .upper()
        )

    print(f"Intent: {intent}")
    print(f"Reference: {reference}")

    # -------------------------------------------------------------
    # Intent routing
    # -------------------------------------------------------------

    if intent == "CheckCaseStatus":

        message = check_case_status(reference)

    elif intent == "RequestDocument":

        message = request_document(reference)

    elif intent == "SpeakToAdviser":

        message = speak_to_adviser()

    else:

        message = (
            "I'm sorry, I don't understand that request."
        )

    # -------------------------------------------------------------
    # Response back to Lex
    # -------------------------------------------------------------

    return {
        "sessionState": {
            "dialogAction": {
                "type": "Close"
            },
            "intent": {
                "name": intent,
                "state": "Fulfilled"
            }
        },
        "messages": [
            {
                "contentType": "PlainText",
                "content": message
            }
        ]
    }