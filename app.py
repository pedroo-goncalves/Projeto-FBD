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
@app.route('/login', methods=['GET', 'POST']) # <--- Adicionado 'GET'
def login():
    # Se o utilizador já estiver logado, manda-o para o dashboard
    if 'user_id' in session:
        return redirect(url_for('dashboard'))

    if request.method == 'POST':
        nif = request.form.get('nif')
        senha_introduzida = request.form.get('senha')
        
        hash_introduzido = hashlib.sha256(senha_introduzida.encode()).hexdigest()

        try:
            conn = get_db_connection()
            cursor = conn.cursor()
            cursor.execute("EXEC sp_obterLogin ?", (nif,))
            user = cursor.fetchone()
            conn.close()

            if user and hash_introduzido == user[1]:
                session['user_id'] = user[0]
                session['user_name'] = user[3]
                session['perfil'] = user[2]
                return redirect(url_for('dashboard'))
            else:
                flash('NIF ou Palavra-passe incorretos.', 'danger')
        except Exception as e:
            flash(f"Erro técnico no login: {e}", "danger")

    # Se for GET (ou falha no login), mostra a página de login
    return render_template('login.html')

# ------------------------------------------------------------------
# ROTA 2: LOGOUT
# ------------------------------------------------------------------
@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

@app.route('/aceitar_pedido/<int:id_pedido>')
def aceitar_pedido(id_pedido):
    if 'user_id' not in session: return redirect(url_for('login'))
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # A SP trata de tudo: Aceita o pedido e cria o vínculo clínico
        cursor.execute("EXEC sp_aceitarPedido ?, ?", (id_pedido, session['user_id']))
        
        conn.commit()
        conn.close()
        flash('Pedido aceite! O paciente foi adicionado à sua lista.', 'success')
    except Exception as e:
        flash(f'Erro ao processar pedido: {e}', 'danger')
        
    return redirect(url_for('dashboard'))
# ------------------------------------------------------------------
# ROTA 3: LISTAR MEUS PACIENTES
# ------------------------------------------------------------------
@app.route('/pacientes')
def pacientes():
    if not is_logged_in(): return redirect(url_for('login'))
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        # Nova SP de listagem com filtro de perfil
        cursor.execute("EXEC sp_listarPacientesSGA ?, ?", (session['user_id'], session['perfil']))
        lista = cursor.fetchall()
        conn.close()
        return render_template('pacientes.html', pacientes=lista, nome_user=session.get('user_name'))
    except Exception as e:
        flash(f"Erro ao listar: {e}", "danger")
        return redirect(url_for('dashboard'))

@app.route('/pacientes/adicionar', methods=['POST'])
def adicionar_paciente():
    # Apenas Admin
    if session.get('perfil') != 'admin':
        flash("Acesso negado.", "danger")
        return redirect(url_for('pacientes'))

    # Dados do formulário
    nif = request.form.get('nif')
    nome = request.form.get('nome')
    data_nasc = request.form.get('data_nasc')
    tel = request.form.get('telefone')
    email = request.form.get('email')
    obs = request.form.get('observacoes')

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # 1. Upsert da Pessoa (SP do Bernardo)
        cursor.execute("EXEC sp_guardarPessoa ?, ?, ?, ?, ?", (nif, nome, data_nasc, tel, email))
        
        # 2. Inserir Paciente (SP do Bernardo)
        # Nota: O parâmetro OUTPUT @id_paciente é ignorado aqui por simplicidade
        cursor.execute("DECLARE @id_out INT; EXEC sp_inserirPaciente @NIF=?, @data_inscricao=?, @observacoes=?, @id_paciente=@id_out OUTPUT", 
                       (nif, datetime.now().date(), obs))
        
        conn.commit()
        conn.close()
        flash("Paciente registado com sucesso!", "success")
    except Exception as e:
        flash(f"Erro ao registar: {e}", "danger")

    return redirect(url_for('pacientes'))

@app.route('/admin/remover_paciente/<int:id_paciente>')
def remover_paciente(id_paciente):
    # Segurança: Apenas admins podem desativar fichas de pacientes
    if session.get('perfil') != 'admin':
        flash('Acesso negado.', 'danger')
        return redirect(url_for('pacientes'))

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_desativarPaciente ?", (id_paciente,))
        conn.commit()
        conn.close()
        flash('Ficha do paciente desativada com sucesso.', 'success')
    except Exception as e:
        flash(f'Erro ao desativar paciente: {e}', 'danger')

    return redirect(url_for('pacientes'))

@app.route('/admin/pacientes/arquivo')
def pacientes_arquivo():
    if session.get('perfil') != 'admin':
        return redirect(url_for('pacientes'))
    
    lista_inativos = []
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_listarPacientesInativos")
        lista_inativos = cursor.fetchall()
        conn.close()
    except Exception as e:
        flash(f"Erro ao carregar arquivo: {e}", "danger")

    return render_template('pacientes_arquivo.html', 
                           pacientes=lista_inativos, 
                           nome_user=session.get('user_name'))

@app.route('/admin/ativar_paciente/<int:id_paciente>')
def ativar_paciente(id_paciente):
    if session.get('perfil') != 'admin':
        return redirect(url_for('pacientes'))

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_ativarPaciente ?", (id_paciente,))
        conn.commit()
        conn.close()
        flash('Paciente recuperado com sucesso!', 'success')
    except Exception as e:
        flash(f'Erro ao recuperar: {e}', 'danger')

    return redirect(url_for('pacientes_arquivo'))


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

@app.route('/pacientes/detalhes/<int:id_paciente>')
def pacientes_detalhes(id_paciente):
    if 'user_id' not in session: return redirect(url_for('login'))

    detalhes = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Chamada da SP que valida o acesso (Admin ou Vinculado)
        # Os parâmetros são: ID do Paciente, ID do utilizador logado e o seu Perfil
        cursor.execute("EXEC sp_obterFichaCompletaPaciente ?, ?, ?", 
                       (id_paciente, session['user_id'], session['perfil']))
        
        detalhes = cursor.fetchone()
        conn.close()

        if not detalhes:
            flash("Paciente não encontrado.", "warning")
            return redirect(url_for('pacientes'))

    except Exception as e:
        # Se a SP lançar o erro de "Acesso Negado", ele será capturado aqui
        flash(f"{e}", "danger")
        return redirect(url_for('pacientes'))

    return render_template('pacientes_detalhes.html', 
                           p=detalhes, 
                           nome_user=session.get('user_name'))

# --- ROTA PARA ATUALIZAR OBSERVAÇÕES (POST DO MODAL) ---
@app.route('/pacientes/atualizar_obs', methods=['POST'])
def atualizar_obs_paciente():
    if 'user_id' not in session: return redirect(url_for('login'))

    id_p = request.form.get('id_paciente')
    novas_obs = request.form.get('novas_obs')

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        # Usa a SP original do Bernardo
        cursor.execute("EXEC sp_atualizarObservacoesPaciente @id=?, @obs=?", (id_p, novas_obs))
        conn.commit()
        conn.close()
        flash("Observações clínicas atualizadas com sucesso!", "success")
    except Exception as e:
        flash(f"Erro ao atualizar: {e}", "danger")

    return redirect(url_for('pacientes_detalhes', id_paciente=id_p))
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
    
    lista_equipa = []
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        # Garante que a procedure devolve 6 colunas (id no index 5)
        cursor.execute("EXEC sp_listarEquipa")
        lista_equipa = cursor.fetchall()
        conn.close()
    except Exception as e:
        flash(f'Erro ao carregar equipa: {e}', 'danger')

    return render_template('equipa.html', 
                           equipa=lista_equipa, 
                           nome_user=session.get('user_name'),
                           now_date=datetime.now().strftime('%Y-%m-%d'))

@app.route('/admin/criar_funcionario', methods=['POST'])
def criar_funcionario():
    if session.get('perfil') != 'admin':
        flash('Acesso negado.', 'danger')
        return redirect(url_for('equipa'))

    # 1. Recolha de Dados com Validação Python
    nif = request.form.get('nif', '').strip()
    telemovel = request.form.get('telemovel', '').strip()
    nome = request.form.get('nome', '').strip()
    email = request.form.get('email', '').strip()
    data_nasc = request.form.get('data_nasc')
    perfil = request.form.get('perfil')
    senha = request.form.get('senha')

    # Validação de Segurança (Backend)
    if len(nif) != 9 or not nif.isdigit():
        flash('NIF inválido: deve ter 9 dígitos.', 'danger')
        return redirect(url_for('equipa'))

    # 2. Tratamento de Campos Opcionais (Evita Erro 8114)
    cedula = request.form.get('cedula') or None
    categoria = request.form.get('categoria')
    contrato_tipo = request.form.get('contrato_tipo') or None
    ordem = request.form.get('ordem') or None
    
    remuneracao = request.form.get('remuneracao')
    remuneracao = float(remuneracao) if remuneracao and remuneracao.strip() != "" else None

    # 3. Hash da Password e Execução
    hash_pw = hashlib.sha256(senha.encode()).hexdigest()

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_criarFuncionario ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?", 
                       (nif, nome, data_nasc, telemovel, email, hash_pw, perfil, cedula, 
                        categoria, contrato_tipo, ordem, remuneracao))
        conn.commit()
        conn.close()
        flash(f'Profissional {nome} registado!', 'success')
    except Exception as e:
        flash(f'Erro na Base de Dados: {e}', 'danger')

    return redirect(url_for('equipa'))

@app.route('/admin/remover_funcionario/<int:id_trabalhador>')
def remover_funcionario(id_trabalhador):
    if session.get('perfil') != 'admin':
        flash('Acesso negado.', 'danger')
        return redirect(url_for('equipa'))

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_desativarFuncionario ?", (id_trabalhador,))
        conn.commit()
        conn.close()
        flash('Acesso desativado.', 'success')
    except Exception as e:
        flash(f'Erro ao desativar: {e}', 'danger')

    return redirect(url_for('equipa'))

@app.route('/admin/equipa/arquivo')
def equipa_arquivo():
    if session.get('perfil') != 'admin':
        return redirect(url_for('equipa'))
    
    lista_inativos = []
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_listarEquipaInativa")
        lista_inativos = cursor.fetchall()
        conn.close()
    except Exception as e:
        flash(f"Erro ao carregar arquivo da equipa: {e}", "danger")

    return render_template('equipa_arquivo.html', 
                           equipa=lista_inativos, 
                           nome_user=session.get('user_name'))

@app.route('/admin/ativar_funcionario/<int:id_trabalhador>')
def ativar_funcionario(id_trabalhador):
    if session.get('perfil') != 'admin':
        return redirect(url_for('equipa'))

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_ativarFuncionario ?", (id_trabalhador,))
        conn.commit()
        conn.close()
        flash('Acesso do funcionário reativado com sucesso!', 'success')
    except Exception as e:
        flash(f'Erro ao reativar: {e}', 'danger')

    return redirect(url_for('equipa_arquivo'))

@app.route('/equipa/detalhes/<int:id_trabalhador>')
def equipa_detalhes(id_trabalhador):
    if 'user_id' not in session: return redirect(url_for('login'))

    trabalhador = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_obterDetalhesTrabalhador ?", (id_trabalhador,))
        trabalhador = cursor.fetchone()
        conn.close()
        
        if not trabalhador:
            flash("Colaborador não encontrado.", "warning")
            return redirect(url_for('equipa'))
            
    except Exception as e:
        flash(f"Erro ao carregar detalhes: {e}", "danger")
        return redirect(url_for('equipa'))

    return render_template('equipa_detalhes.html', 
                           t=trabalhador, 
                           nome_user=session.get('user_name'))








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
