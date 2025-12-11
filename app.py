import os
from dotenv import load_dotenv, dotenv_values 

from flask import Flask, render_template
from flask_sqlalchemy import SQLAlchemy
import urllib

app = Flask(__name__)
load_dotenv()

server = os.getenv("SERVER")
database = os.getenv("DATABASE")
username = os.getenv("UID")
password = os.getenv("PWD")

params = urllib.parse.quote_plus(
    f'DRIVER={{ODBC Driver 17 for SQL Server}};'
    f'SERVER={server};'
    f'DATABASE={database};'
    f'UID={username};'
    f'PWD={password};'
)

app.config['SQLALCHEMY_DATABASE_URI'] = f"mssql+pyodbc:///?odbc_connect={params}"
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db = SQLAlchemy(app)

# --- 2. OS MODELOS (Mapeamento das tuas tabelas SGA) ---
# --- OS MODELOS ---
class Pessoa(db.Model):
    __tablename__ = 'SGA_PESSOA'
    nif = db.Column('NIF', db.String(9), primary_key=True)
    nome = db.Column(db.String(50))

class Paciente(db.Model):
    __tablename__ = 'SGA_PACIENTE'
    id_paciente = db.Column(db.Integer, primary_key=True)
    nif = db.Column('NIF', db.String(9), db.ForeignKey('SGA_PESSOA.NIF'))
    dados_pessoais = db.relationship('Pessoa', backref='paciente')

# --- A ROTA ---
@app.route('/')
def index():
    try:
        # Busca os dados
        pacientes = Paciente.query.all()
        
        # O SEGREDO ESTÁ AQUI: render_template processa os símbolos {{ }}
        return render_template('index.html', lista=pacientes)
        
    except Exception as e:
        # Se der erro, mostra no ecrã
        return f"<h1 style='color:red'>Erro: {e}</h1>"

if __name__ == '__main__':
    app.run(debug=True)


