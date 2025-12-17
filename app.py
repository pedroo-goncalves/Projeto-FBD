"""
SGA - Centro de Psicologia
Flask Web Application.
"""

from flask import Flask, render_template
from persistence.session import test_connection

app = Flask(__name__)

# Rota para a página inicial
@app.route('/')
@app.route('/index.html')
def index():
    return render_template('index.html')

@app.route('/pacientes.html')
def pacientes():
    return render_template('pacientes.html')

@app.route('/equipa.html')
def equipa():
    return render_template('equipa.html')

# Rota para a Agenda
@app.route('/agenda.html')
def agenda():
    return render_template('agenda.html')

# Rota para os Relatórios (A que estava a dar erro)
@app.route('/relatorios.html')
def relatorios():
    return render_template('relatorios.html')

# Rota para o Login
@app.route('/login.html')
def login():
    return render_template('login.html')

if __name__ == '__main__':
    app.run(debug=True)