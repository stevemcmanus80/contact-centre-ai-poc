from crm import get_customer
from bedrock import generate_customer_response

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
