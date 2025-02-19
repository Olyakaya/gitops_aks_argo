import os
from flask import Flask

app = Flask(__name__)

@app.route("/")
def hello():
    # Read an environment variable called "GREETING_MESSAGE"
    message = os.getenv("GREETING_MESSAGE", "Hello, Azure! It's first deploy by Argo")
    return message

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
