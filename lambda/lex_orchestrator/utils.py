def normalise_reference(reference):

    if not reference:
        return "UNKNOWN"

    return (
        reference
        .strip()
        .upper()
    )