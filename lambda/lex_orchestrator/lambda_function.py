import json
from intents import (
    check_case_status,
    request_document,
    speak_to_adviser,
)
from utils import normalise_reference

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
        reference = normalise_reference(
            slots["ReferenceNumber"]["value"]["interpretedValue"]
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