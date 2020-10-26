import json

def handler(event, context):
    print("Received event: " + json.dumps(event, indent=2).replace('\n', ''))
    # This is the main function

