import os
import hashlib
from datetime import datetime
from functools import wraps
from flask import Flask, render_template, request, redirect, url_for, session, flash, jsonify
from dotenv import load_dotenv

# --- IMPORTS DA CAMADA DE PERSISTÊNCIA ---
from persistence.session import get_db_connection 
from persistence.pacientes import contar_pacientes, criar_paciente_via_agenda
from persistence.pedidos import contar_pedidos_pendentes
from persistence.atendimentos import contar_atendimentos_hoje, obter_horarios_livres, listar_eventos_calendario, obter_detalhes_atendimento, editar_agendamento, cancelar_agendamento
from persistence.salas import contar_salas_livres
from persistence.trabalhadores import medicos_agenda_dropdown, obter_dados_login
from persistence.dashboard import obter_totais_dashboard, listar_proximas_consultas

load_dotenv()

app = Flask(__name__)
app.secret_key = os.getenv('SECRET_KEY')

# ==============================================================================
# DECORATORS (Segurança e Modularidade)
# ==============================================================================

def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'user_id' not in session:
            flash('Por favor, inicie sessão para aceder.', 'warning')
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated_function

def admin_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'user_id' not in session:
            return redirect(url_for('login'))
        if session.get('perfil') != 'admin':
            flash('Acesso negado. Apenas administradores.', 'danger')
            return redirect(request.referrer or url_for('dashboard'))
        return f(*args, **kwargs)
    return decorated_function

# ==============================================================================
# AUTENTICAÇÃO
# ==============================================================================

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        nif = request.form.get('nif')
        senha = request.form.get('senha')

        if not nif or not senha:
            flash('Preencha todos os campos.', 'warning')
            return render_template('login.html')

        conn = get_db_connection()
        cursor = conn.cursor()
        user = obter_dados_login(cursor, nif)
        conn.close()

        if user:
            hash_introduzido = hashlib.sha256(senha.encode()).hexdigest()
            if hash_introduzido == user[1]:
                session['user_id'] = user[0]
                session['perfil'] = user[2]
                session['user_name'] = user[3]
                return redirect(url_for('dashboard'))

        flash('NIF ou palavra-passe incorretos.', 'danger')

    return render_template('login.html')

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

# ==============================================================================
# DASHBOARD E LISTAGENS PRINCIPAIS
# ==============================================================================

@app.route('/')
@app.route('/dashboard')
@login_required
def dashboard():
    conn = get_db_connection()
    cursor = conn.cursor()
    
    user_id = session.get('user_id')
    perfil = session.get('perfil')
    
    # --- CORREÇÃO DO NOME (Safety Check) ---
    # Tenta obter da sessão. Se falhar, vai à BD buscar.
    nome_user = session.get('nome_user')
    if not nome_user:
        # Busca rápida do nome se não estiver em sessão
        cursor.execute("SELECT nome FROM SGA_PESSOA p JOIN SGA_TRABALHADOR t ON p.NIF = t.NIF WHERE t.id_trabalhador = ?", (user_id,))
        res = cursor.fetchone()
        nome_user = res[0] if res else 'Utilizador'
        # Opcional: Atualizar sessão para a próxima vez ser rápido
        session['nome_user'] = nome_user

    # Chamadas Modulares (Persistência)
    totais = obter_totais_dashboard(cursor, user_id, perfil)
    proximas = listar_proximas_consultas(cursor, user_id, perfil)
    
    conn.close()
    
    return render_template('dashboard.html', 
                           totais=totais,
                           proximas_consultas=proximas,
                           nome_user=nome_user) # Agora vai sempre preenchido

@app.route('/pacientes')
@login_required
def pacientes():
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_listarPacientesSGA ?, ?", (session['user_id'], session['perfil']))
        lista = cursor.fetchall()
        conn.close()
        return render_template('pacientes.html', pacientes=lista, nome_user=session.get('user_name'))
    except Exception as e:
        flash(f"Erro ao listar: {e}", "danger")
        return redirect(url_for('dashboard'))

@app.route('/equipa')
@login_required
def equipa():
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_listarEquipa")
        lista = cursor.fetchall()
        conn.close()
    except Exception as e:
        flash(f'Erro ao carregar equipa: {e}', 'danger')
        lista = []
    return render_template('equipa.html', equipa=lista, nome_user=session.get('user_name'),
                           now_date=datetime.now().strftime('%Y-%m-%d'))

# ==============================================================================
# AGENDA E MARCAÇÕES (ESTAS ERAM AS QUE FALTAVAM!)
# ==============================================================================

@app.route('/agenda')
@login_required
def agenda():
    conn = get_db_connection()
    cursor = conn.cursor()
    lista_medicos = []
    lista_pacientes = []

    try:
        # 1. Carregar Médicos (Para o Admin)
        lista_medicos = medicos_agenda_dropdown(cursor)
        
        # 2. Carregar Pacientes
        cursor.execute("EXEC sp_ListarPacientesParaAgenda ?, ?", (session['user_id'], session['perfil']))
        rows = cursor.fetchall()
        lista_pacientes = [{'nif': r[2], 'nome': r[1]} for r in rows]

    except Exception as e:
        print(f"Erro agenda: {e}")
    finally:
        conn.close()

    return render_template('agenda.html', nome_user=session.get('user_name'),
                           medicos=lista_medicos, pacientes=lista_pacientes)

@app.route('/criar_agendamento', methods=['POST'])
@login_required
def criar_agendamento():
    nif_paciente = request.form.get('nif_paciente')
    duracao = int(request.form.get('duracao', 60))
    
    if session['perfil'] == 'colaborador':
        id_medico = session['user_id']
    else:
        id_medico = request.form.get('id_medico')

    data_str = request.form.get('data')
    hora_str = request.form.get('hora')
    is_online_raw = request.form.get('is_online')
    preferencia_online = 1 if is_online_raw else 0

    if not all([nif_paciente, id_medico, data_str, hora_str]):
        flash('Preencha todos os campos obrigatórios.', 'warning')
        return redirect(url_for('agenda'))

    try:
        data_completa = f"{data_str} {hora_str}:00"
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_criarAgendamento ?, ?, ?, ?, ?", 
                       (nif_paciente, id_medico, data_completa, preferencia_online, duracao))
        conn.commit()
        conn.close()
        flash('Consulta agendada com sucesso!', 'success')
    except Exception as e:
        msg = str(e)
        if "50009" in msg: msg = "Paciente não encontrado."
        elif "50010" in msg: msg = "Médico ocupado nessa hora."
        elif "50011" in msg: msg = "Não há salas disponíveis."
        flash(f'Erro: {msg}', 'danger')

    return redirect(url_for('agenda'))

# ==============================================================================
# DETALHES E RELATÓRIOS (TAMBÉM FALTAVAM)
# ==============================================================================

@app.route('/pacientes/detalhes/<int:id_paciente>')
@login_required
def pacientes_detalhes(id_paciente):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_obterFichaCompletaPaciente ?, ?, ?", 
                       (id_paciente, session['user_id'], session['perfil']))
        detalhes = cursor.fetchone()
        conn.close()
        return render_template('pacientes_detalhes.html', p=detalhes, nome_user=session['user_name'])
    except Exception as e:
        flash(f"Erro de Acesso: {e}", "danger")
        return redirect(url_for('pacientes'))

@app.route('/equipa/detalhes/<int:id_trabalhador>')
@login_required
def equipa_detalhes(id_trabalhador):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_obterDetalhesTrabalhador ?, ?", (id_trabalhador, session['perfil']))
        trabalhador = cursor.fetchone()
        conn.close()
        return render_template('equipa_detalhes.html', t=trabalhador, nome_user=session['user_name'])
    except Exception as e:
        flash(f"Acesso Negado: {e}", "danger")
        return redirect(url_for('equipa'))

@app.route('/relatorios')
@login_required
def relatorios():
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_listarRelatoriosVinculados ?", (session['user_id'],))
        lista = cursor.fetchall()
        conn.close()
    except Exception as e:
        flash(f'Erro ao carregar relatórios: {e}', 'warning')
        lista = []
    return render_template('relatorios.html', relatorios=lista, nome_user=session.get('user_name'))

# ==============================================================================
# AÇÕES DE PACIENTES E EQUIPA (CRIAR, EDITAR, ARQUIVAR)
# ==============================================================================

@app.route('/criar_paciente', methods=['POST'])
@login_required
def criar_paciente():
    dados = {k: request.form.get(k) for k in ['nome', 'nif', 'data_nasc', 'email', 'telefone', 'observacoes']}
    user_id = session['user_id']
    user_perfil = session['perfil']
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        if user_perfil == 'colaborador': 
            cursor.execute("EXEC sp_guardarPessoa ?, ?, ?, ?, ?", 
                           (dados['nif'], dados['nome'], dados['data_nasc'], dados['telefone'], dados['email']))
            data_hoje = datetime.now().strftime('%Y-%m-%d')
            cursor.execute("EXEC sp_inserirPaciente @NIF=?, @data_inscricao=?, @observacoes=?, @id_medico_responsavel=?", 
                           (dados['nif'], data_hoje, dados['observacoes'], user_id))
            flash('Paciente registado e vinculado a si!', 'success')
        else:
            cursor.execute("EXEC sp_AdmissaoComPedido ?, ?, ?, ?, ?, ?, ?, ?", 
                           (dados['nif'], dados['nome'], dados['data_nasc'], dados['telefone'], 
                            dados['email'], dados['observacoes'], user_id, 'Triagem Inicial'))
            flash('Paciente registado. Pedido de triagem criado!', 'warning')
        
        conn.commit()
        conn.close()
    except Exception as e:
        flash(f'Erro ao gravar: {e}', 'danger')
    return redirect(url_for('pacientes'))

@app.route('/pacientes/atualizar_obs', methods=['POST'])
@login_required
def atualizar_obs_paciente():
    id_p = request.form.get('id_paciente')
    novas_obs = request.form.get('novas_obs')
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_atualizarObservacoesPaciente @id=?, @obs=?", (id_p, novas_obs))
        conn.commit()
        conn.close()
        flash("Observações atualizadas!", "success")
    except Exception as e:
        flash(f"Erro ao atualizar: {e}", "danger")
    return redirect(url_for('pacientes_detalhes', id_paciente=id_p))

@app.route('/aceitar_pedido/<int:id_pedido>')
@login_required
def aceitar_pedido(id_pedido):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_aceitarPedido ?, ?", (id_pedido, session['user_id']))
        conn.commit()
        conn.close()
        flash('Pedido aceite!', 'success')
    except Exception as e:
        flash(f'Erro ao processar pedido: {e}', 'danger')
    return redirect(url_for('dashboard'))

# --- ROTAS DE ADMIN ---

@app.route('/admin/criar_funcionario', methods=['POST'])
@admin_required
def criar_funcionario():
    nif = request.form.get('nif', '').strip()
    if len(nif) != 9 or not nif.isdigit():
        flash('NIF inválido.', 'danger')
        return redirect(url_for('equipa'))

    hash_pw = hashlib.sha256(request.form.get('senha').encode()).hexdigest()
    remuneracao = request.form.get('remuneracao')
    remuneracao = float(remuneracao) if remuneracao and remuneracao.strip() else None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_criarFuncionario ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?", 
                       (nif, request.form.get('nome'), request.form.get('data_nasc'), 
                        request.form.get('telemovel'), request.form.get('email'), 
                        hash_pw, request.form.get('perfil'), request.form.get('cedula') or None, 
                        request.form.get('categoria'), request.form.get('contrato_tipo') or None, 
                        request.form.get('ordem') or None, remuneracao))
        conn.commit()
        conn.close()
        flash('Profissional registado!', 'success')
    except Exception as e:
        flash(f'Erro na BD: {e}', 'danger')
    return redirect(url_for('equipa'))

@app.route('/admin/remover_funcionario/<int:id_trabalhador>')
@admin_required
def remover_funcionario(id_trabalhador):
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

@app.route('/admin/ativar_funcionario/<int:id_trabalhador>')
@admin_required
def ativar_funcionario(id_trabalhador):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_ativarFuncionario ?", (id_trabalhador,))
        conn.commit()
        conn.close()
        flash('Funcionário reativado.', 'success')
    except Exception as e:
        flash(f'Erro: {e}', 'danger')
    return redirect(url_for('equipa_arquivo'))

@app.route('/admin/equipa/arquivo')
@admin_required
def equipa_arquivo():
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_listarEquipaInativa")
        lista = cursor.fetchall()
        conn.close()
    except Exception as e:
        flash(f"Erro: {e}", "danger")
        lista = []
    return render_template('equipa_arquivo.html', equipa=lista, nome_user=session.get('user_name'))

@app.route('/admin/remover_paciente/<int:id_paciente>')
@admin_required
def remover_paciente(id_paciente):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_desativarPaciente ?", (id_paciente,))
        conn.commit()
        conn.close()
        flash('Paciente desativado.', 'success')
    except Exception as e:
        flash(f'Erro: {e}', 'danger')
    return redirect(url_for('pacientes'))

@app.route('/admin/ativar_paciente/<int:id_paciente>')
@admin_required
def ativar_paciente(id_paciente):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_ativarPaciente ?", (id_paciente,))
        conn.commit()
        conn.close()
        flash('Paciente recuperado!', 'success')
    except Exception as e:
        flash(f'Erro: {e}', 'danger')
    return redirect(url_for('pacientes_arquivo'))

@app.route('/admin/pacientes/arquivo')
@admin_required
def pacientes_arquivo():
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_listarPacientesInativos")
        lista = cursor.fetchall()
        conn.close()
    except Exception as e:
        flash(f"Erro: {e}", "danger")
        lista = []
    return render_template('pacientes_arquivo.html', pacientes=lista, nome_user=session.get('user_name'))

# ==============================================================================
# API JSON
# ==============================================================================

@app.route('/api/eventos')
@login_required
def api_eventos():
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # Ler filtros do URL
    filtro_medico = request.args.get('filtro_medico')
    filtro_paciente_nif = request.args.get('filtro_paciente')
    
    # Passar para a persistência
    rows = listar_eventos_calendario(
        cursor, 
        session['user_id'], 
        session.get('perfil'),
        filtro_medico_id=filtro_medico,
        filtro_paciente_nif=filtro_paciente_nif
    )
    conn.close()
    
    eventos = []
    for row in rows:
        titulo = row[1]
        if session.get('perfil') == 'admin':
            titulo = f"[{row[5].split()[0]}] {row[1]}"

        eventos.append({
            'id': row[0],
            'num_atendimento': row[0], # Redundância segura
            'title': titulo,
            'start': row[2].isoformat(),
            'end': row[3].isoformat(),
            'color': '#198754' if row[4] == 'finalizado' else ('#dc3545' if row[4] == 'falta' else '#0d6efd')
        })
        
    return jsonify(eventos)

@app.route('/api/criar_paciente_rapido', methods=['POST'])
@login_required
def criar_paciente_rapido():
    data = request.json 
    nif, nome, telemovel, data_nasc = data.get('nif'), data.get('nome'), data.get('telemovel'), data.get('data_nasc')
    
    if not all([nif, nome, telemovel, data_nasc]):
        return jsonify({'erro': 'Preencha todos os campos.'}), 400

    conn = get_db_connection()
    cursor = conn.cursor()

    try:
        new_id = criar_paciente_via_agenda(cursor, nif, nome, telemovel, data_nasc)
        conn.commit()
        return jsonify({'sucesso': True, 'id': new_id, 'nif': nif, 'nome': nome})
    except Exception as e:
        conn.rollback()
        msg = str(e)
        if "50003" in msg or "PRIMARY KEY" in msg:
             return jsonify({'erro': 'Já existe um paciente com este NIF.'}), 400
        return jsonify({'erro': f'Erro técnico: {msg}'}), 500
    finally:
        conn.close()

@app.route('/api/horarios-disponiveis')
def api_horarios():
    id_medico = request.args.get('medico')
    data = request.args.get('data')
    is_online_raw = request.args.get('is_online')
    is_online = 1 if is_online_raw == '1' else 0
    duracao = request.args.get('duracao', 60, type=int)
    
    # Novo parâmetro (pode ser None ou vazio)
    ignorar_id = request.args.get('ignorar_id', type=int)

    if not id_medico or not data: return jsonify([])

    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        # Passa o ignorar_id para a persistência
        slots = obter_horarios_livres(cursor, id_medico, data, is_online, duracao, ignorar_id)
    except Exception as e:
        print(f"Erro api horarios: {e}")
        slots = []
    finally:
        conn.close()
    return jsonify(slots)

@app.route('/api/atendimento/<int:id_atendimento>')
@login_required
def api_detalhes_atendimento(id_atendimento):
    conn = get_db_connection()
    cursor = conn.cursor()
    detalhes = obter_detalhes_atendimento(cursor, id_atendimento)
    conn.close()
    
    if detalhes:
        # Converter datas para string ISO para o JS ler
        detalhes['inicio_iso'] = detalhes['inicio'].strftime('%Y-%m-%dT%H:%M')
        detalhes['data_iso'] = detalhes['inicio'].strftime('%Y-%m-%d')
        detalhes['hora_iso'] = detalhes['inicio'].strftime('%H:%M')
        return jsonify(detalhes)
    return jsonify({'erro': 'Não encontrado'}), 404

@app.route('/editar_agendamento', methods=['POST'])
@login_required
def rota_editar_agendamento():
    id_atendimento = request.form.get('id_atendimento')
    data_str = request.form.get('data')
    hora_str = request.form.get('hora')
    duracao = int(request.form.get('duracao'))
    
    try:
        data_completa = f"{data_str} {hora_str}:00"
        
        conn = get_db_connection()
        cursor = conn.cursor()
        editar_agendamento(cursor, id_atendimento, data_completa, duracao)
        conn.commit()
        conn.close()
        flash('Agendamento atualizado com sucesso!', 'success')
    except Exception as e:
        flash(f'Erro ao atualizar: {e}', 'danger')
        
    return redirect(url_for('agenda'))

@app.route('/cancelar_agendamento/<int:id_atendimento>')
@login_required
def rota_cancelar_agendamento(id_atendimento):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cancelar_agendamento(cursor, id_atendimento)
        conn.commit()
        conn.close()
        flash('Consulta cancelada com sucesso.', 'success')
    except Exception as e:
        flash(f'Erro ao cancelar: {e}', 'danger')
        
    return redirect(request.referrer or url_for('agenda'))

if __name__ == '__main__':
    app.run(debug=True)