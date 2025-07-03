import spacy 

nlp = spacy.load("en_core_web_sm")

COMMAND_KEYWORDS = {
    "insert": ["insert", "add", "schedule", "assign"],
    "delete": ["delete", "remove", "cancel", "discard"],
}

def get_the_command():
    user_input = input("🔍 What would you like to do? (e.g. 'Add a new task')\n> ").lower()
    doc = nlp(user_input)

    # Check for known keywords in user input
    for token in doc:
        for command, keywords in COMMAND_KEYWORDS.items():
            if token.lemma_ in keywords:
                return command

    print("⚠️ Could not detect a valid command. Try 'insert' or 'delete'.")
    return None

get_the_command()