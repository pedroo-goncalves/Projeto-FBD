import os
import hashlib
from datetime import datetime
from flask import Flask, render_template, request, redirect, url_for, session, flash
from dotenv import load_dotenv

# Importação da conexão confisgurada no teu projeto
from persistence.session import get_db_connection 

# Imports dos pacientes
from persistence.pacientes import contar_pacientes

# Imports dos pedidos
from persistence.pedidos import contar_pedidos_pendentes

# Imports dos atendimentos
from persistence.atendimentos import contar_atendimentos_hoje, obter_horarios_livres

# Imports dos trabalhadores
from persistence.trabalhadores import medicos_agenda_dropdown

load_dotenv()

app = Flask(__name__)
# A secret_key permite o funcionamento das mensagens flash e sessões
app.secret_key = os.getenv('SECRET_KEY', 'chave-de-seguranca-padrao-123')


def is_logged_in():
    return 'user_id' in session

# ------------------------------------------------------------------
# ROTA 1: LOGIN (Validação SHA256 Pura)
# ------------------------------------------------------------------
@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        nif = request.form.get('nif')
        senha = request.form.get('senha')

        try:
            conn = get_db_connection()
            cursor = conn.cursor()
            
            # Chama a Stored Procedure para obter os dados do trabalhador
            cursor.execute("EXEC sp_obterLogin ?", (nif,))
            user = cursor.fetchone()
            conn.close()

            if user:
                # 1. Transforma a senha digitada em Hash SHA256 (igual ao SQL)
                hash_introduzido = hashlib.sha256(senha.encode()).hexdigest()
                
                # 2. Compara o hash gerado com o hash que está na BD
                if hash_introduzido == user[1]:
                    session['user_id'] = user[0]
                    session['user_name'] = user[3]
                    session['perfil'] = user[2]
                    return redirect(url_for('pacientes'))
                else:
                    flash('Credenciais inválidas.', 'danger')
            else:
                flash('Credenciais inválidas.', 'danger')

        except Exception as e:
            flash(f'Erro de sistema: {e}', 'danger')

    return render_template('login.html')

# ------------------------------------------------------------------
# ROTA 2: LOGOUT
# ------------------------------------------------------------------
@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

# ------------------------------------------------------------------
# ROTA 3: LISTAR MEUS PACIENTES
# ------------------------------------------------------------------
@app.route('/')
@app.route('/pacientes')
def pacientes():
    if not is_logged_in(): return redirect(url_for('login'))

    lista_pacientes = []
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        # Filtra pacientes através da SP que verifica os vínculos
        cursor.execute("EXEC sp_listarMeusPacientes ?", (session['user_id'],))
        lista_pacientes = cursor.fetchall()
        conn.close()
    except Exception as e:
        flash(f'Erro ao carregar dados: {e}', 'warning')

    return render_template('pacientes.html', 
                           pacientes=lista_pacientes, 
                           nome_user=session.get('user_name'))

# ------------------------------------------------------------------
# ROTA 4: CRIAR NOVO PACIENTE (Lógica nas SPs)
# ------------------------------------------------------------------
@app.route('/criar_paciente', methods=['POST'])
def criar_paciente():
    if not is_logged_in(): return redirect(url_for('login'))

    nome = request.form.get('nome')
    nif = request.form.get('nif')
    data_nasc = request.form.get('data_nasc')
    email = request.form.get('email')
    telefone = request.form.get('telefone')
    observacoes = request.form.get('observacoes')
    
    id_medico = session['user_id']
    data_hoje = datetime.now().strftime('%Y-%m-%d')

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        # Executa as SPs de escrita definidas no SQL
        cursor.execute("EXEC sp_guardarPessoa ?, ?, ?, ?, ?", (nif, nome, data_nasc, telefone, email))
        cursor.execute("EXEC sp_inserirPaciente ?, ?, ?, ?", (nif, data_hoje, observacoes, id_medico))
        
        conn.commit()
        conn.close()
        flash('Paciente registado com sucesso!', 'success')
    except Exception as e:
        flash(f'Erro ao gravar: {e}', 'danger')
    
    return redirect(url_for('pacientes'))

# ------------------------------------------------------------------
# ROTA 5: RELATÓRIOS
# ------------------------------------------------------------------
@app.route('/relatorios')
def relatorios():
    if not is_logged_in(): return redirect(url_for('login'))
    
    lista_relatorios = []
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_listarRelatoriosVinculados ?", (session['user_id'],))
        lista_relatorios = cursor.fetchall()
        conn.close()
    except Exception as e:
        flash(f'Erro ao carregar relatórios: {e}', 'warning')

    return render_template('relatorios.html', 
                           relatorios=lista_relatorios, 
                           nome_user=session.get('user_name'))

# ------------------------------------------------------------------
# OUTRAS ROTAS (EQUIPA E AGENDA)
# ------------------------------------------------------------------
@app.route('/equipa')
def equipa():
    if not is_logged_in(): return redirect(url_for('login'))
    return render_template('equipa.html', nome_user=session.get('user_name'))








@app.route('/agenda')
def agenda():
    if not is_logged_in(): return redirect(url_for('login'))

    conn = get_db_connection()
    cursor = conn.cursor()

    try:
        lista_medicos = medicos_agenda_dropdown(cursor)
    except Exception as e:
        print(f"erro: {e}")
        lista_medicos = []


    return render_template('agenda.html', nome_user=session.get('user_name'),
                           medicos=lista_medicos)

from flask import jsonify, request # Importante adicionar jsonify e request

@app.route('/api/horarios-disponiveis')
def api_horarios():
    # O JavaScript vai enviar ?medico=1&data=2025-12-20
    id_medico = request.args.get('medico')
    data = request.args.get('data')

    if not id_medico or not data:
        return jsonify([]) # Retorna lista vazia se faltar dados

    conn = get_db_connection()
    cursor = conn.cursor()
    slots = obter_horarios_livres(cursor, id_medico, data)
    conn.close()

    return jsonify(slots) # O Python transforma a lista em JSON para o JS ler


@app.route('/dashboard')
def dashboard():
    if not is_logged_in(): return redirect(url_for('login'))

    conn = get_db_connection()
    cursor = conn.cursor()

    try: 
        total_p = contar_pacientes(cursor)
        total_pendentes = contar_pedidos_pendentes(cursor)
        consultas_hoje = contar_atendimentos_hoje(cursor)

    except Exception as e:
        print(f"Erro: {e}")
        total_p = 0
        total_pendentes = 0
        consultas_hoje = {'total': 0, 'online': 0, 'presencial': 0}
    finally:
        cursor.close()
        conn.close()

    return render_template('dashboard.html',
                           nome_user=session.get('user_name'),
                           total_pacientes=total_p, total_pedidos=total_pendentes, consultas=consultas_hoje)

if __name__ == '__main__':
    app.run(debug=True)
