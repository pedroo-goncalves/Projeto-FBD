"""
SGA - Centro de Psicologia
Flask Web Application.
"""

from flask import Flask, render_template
from persistence.session import test_connection

app = Flask(__name__)

@app.route('/')
def index():
    return render_template('index.html')

if __name__ == '__main__':
    if test_connection():
        app.run(debug=True)