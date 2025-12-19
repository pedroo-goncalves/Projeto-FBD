import os
import hashlib
from datetime import datetime
from flask import Flask, render_template, request, redirect, url_for, session, flash, jsonify
from dotenv import load_dotenv

# Importação da conexão confisgurada no teu projeto
from persistence.session import get_db_connection 

# Imports dos pacientes
from persistence.pacientes import contar_pacientes

# Imports dos pedidos
from persistence.pedidos import contar_pedidos_pendentes

# Imports dos atendimentos
from persistence.atendimentos import contar_atendimentos_hoje, obter_horarios_livres

# Imports das salas
from persistence.salas import contar_salas_livres

# Imports dos trabalhadores
from persistence.trabalhadores import medicos_agenda_dropdown

load_dotenv()

app = Flask(__name__)
# A secret_key permite o funcionamento das mensagens flash e sessões
app.secret_key = os.getenv('SECRET_KEY')


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

        if not nif or not senha:
            flash('Preencha todos os campos.', 'warning')
            return render_template('login.html')
        

        try:
            conn = get_db_connection()
            cursor = conn.cursor()

            cursor.execute("EXEC sp_obterLogin ?", (nif,))
            user = cursor.fetchone()
            conn.close()

            if user:
                hash_introduzido = hashlib.sha256(senha.encode()).hexdigest()

                if hash_introduzido == user[1]:
                    session['user_id'] = user[0]
                    session['perfil'] = user[2]
                    session['user_name'] = user[3]
                    return redirect(url_for('dashboard'))

            flash('NIF ou palavra-passe incorretos.', 'danger')

        except Exception:
            flash('Ocorreu um erro interno. Tente novamente mais tarde.', 'danger')

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
    
    user_id = session['user_id']
    user_perfil = session['perfil']
    data_hoje = datetime.now().strftime('%Y-%m-%d')

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # LÓGICA DE NEGÓCIO:
        # Se for um médico a registar, ele quer ficar já com o paciente (Vínculo Imediato).
        # Se for Admin a fazer admissão geral, cria um Pedido para triagem.
        
        if user_perfil == 'colaborador': 
            # O médico regista e fica logo responsável (Cenário A)
            cursor.execute("EXEC sp_guardarPessoa ?, ?, ?, ?, ?", (nif, nome, data_nasc, telefone, email))
            # Passamos user_id como médico responsável para criar o vínculo logo
            cursor.execute("EXEC sp_inserirPaciente @NIF=?, @data_inscricao=?, @observacoes=?, @id_medico_responsavel=?", 
                           (nif, data_hoje, observacoes, user_id))
            flash('Paciente registado e vinculado a si com sucesso!', 'success')

        else:
            # É uma admissão administrativa (Cenário B) -> Gera PEDIDO
            cursor.execute("EXEC sp_AdmissaoComPedido ?, ?, ?, ?, ?, ?, ?, ?", 
                           (nif, nome, data_nasc, telefone, email, observacoes, user_id, 'Triagem Inicial'))
            flash('Paciente registado. Pedido de triagem criado!', 'warning')
        
        conn.commit()
        conn.close()
    except Exception as e:
        flash(f'Erro ao gravar: {e}', 'danger')
    
    return redirect(url_for('pacientes'))

@app.route('/pacientes/detalhes/<int:id_paciente>')
def pacientes_detalhes(id_paciente):
    if 'user_id' not in session: return redirect(url_for('login'))
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        # Validação dupla: quem pede e que perfil tem
        cursor.execute("EXEC sp_obterFichaCompletaPaciente ?, ?, ?", 
                       (id_paciente, session['user_id'], session['perfil']))
        detalhes = cursor.fetchone()
        conn.close()
        
        return render_template('pacientes_detalhes.html', p=detalhes, nome_user=session['user_name'])
    except Exception as e:
        flash(f"Erro de Acesso: {e}", "danger")
        return redirect(url_for('pacientes'))

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
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        # O SQL decide se entrega os dados com base no perfil
        cursor.execute("EXEC sp_obterDetalhesTrabalhador ?, ?", (id_trabalhador, session['perfil']))
        trabalhador = cursor.fetchone()
        conn.close()
        
        return render_template('equipa_detalhes.html', t=trabalhador, nome_user=session['user_name'])
    except Exception as e:
        flash(f"Acesso Negado: {e}", "danger")
        return redirect(url_for('equipa'))

    return render_template('equipa_detalhes.html', 
                           t=trabalhador, 
                           nome_user=session.get('user_name'))







@app.route('/agenda')
def agenda():
    if not is_logged_in(): return redirect(url_for('login'))

    conn = get_db_connection()
    cursor = conn.cursor()

    lista_medicos = []
    lista_pacientes = []

    try:
        # 1. Carregar Médicos (Para o Admin escolher)
        # Se for Colaborador, nem precisava da lista toda, mas o HTML trata disso
        lista_medicos = medicos_agenda_dropdown(cursor)
        
        # 2. Carregar Pacientes (SEGURANÇA: Vê só os seus se for colaborador)
        # Certifica-te que tens a sp_ListarPacientesParaAgenda criada no SQL!
        cursor.execute("EXEC sp_ListarPacientesParaAgenda ?, ?", (session['user_id'], session['perfil']))
        rows = cursor.fetchall()
        
        # Formata para usar no Datalist (NIF como valor, Nome como texto)
        lista_pacientes = [{'nif': r[2], 'nome': r[1]} for r in rows]

    except Exception as e:
        print(f"Erro agenda: {e}")
    finally:
        conn.close()

    return render_template('agenda.html', 
                           nome_user=session.get('user_name'),
                           medicos=lista_medicos,
                           pacientes=lista_pacientes) # Importante enviar isto

# ROTA DE GRAVAR AGENDAMENTO
@app.route('/criar_agendamento', methods=['POST'])
def criar_agendamento():
    if not is_logged_in(): return redirect(url_for('login'))

    nif_paciente = request.form.get('nif_paciente')
    
    # Se for Colaborador, forçamos o ID dele (segurança backend)
    if session['perfil'] == 'colaborador':
        id_medico = session['user_id']
    else:
        id_medico = request.form.get('id_medico')

    data_str = request.form.get('data')
    hora_str = request.form.get('hora')
    
    # CHECKBOX: Se estiver marcado vem '1', senão vem None.
    # Convertemos para 1 ou 0 para o SQL
    is_online_raw = request.form.get('is_online')
    preferencia_online = 1 if is_online_raw else 0

    if not all([nif_paciente, id_medico, data_str, hora_str]):
        flash('Preencha todos os campos obrigatórios.', 'warning')
        return redirect(url_for('agenda'))

    try:
        data_completa = f"{data_str} {hora_str}:00"
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Chama a SP atualizada com o parâmetro extra de Online
        cursor.execute("EXEC sp_criarAgendamento ?, ?, ?, ?", 
                       (nif_paciente, id_medico, data_completa, preferencia_online))
        
        conn.commit()
        conn.close()
        flash('Consulta agendada com sucesso!', 'success')
        
    except Exception as e:
        msg = str(e)
        if "50009" in msg: msg = "Paciente não encontrado (verifique o NIF)."
        elif "50010" in msg: msg = "Médico ocupado nessa hora."
        elif "50011" in msg: msg = "Não há salas disponíveis."
        
        print(f"Erro Agendamento: {e}")
        flash(f'Erro: {msg}', 'danger')

    return redirect(url_for('agenda'))

from flask import jsonify, request # Importante adicionar jsonify e request

@app.route('/api/eventos')
def api_eventos():
    if not is_logged_in(): return jsonify([])

    conn = get_db_connection()
    cursor = conn.cursor()
    
    # Query que junta Atendimento -> Paciente -> Pessoa para obter nomes e datas
    # Filtra para não mostrar cancelados
    query = """
    SELECT 
        A.num_atendimento,
        Pess.nome,
        A.data_inicio,
        A.data_fim,
        A.estado
    FROM SGA_ATENDIMENTO A
    JOIN SGA_PACIENTE_ATENDIMENTO PA ON A.num_atendimento = PA.num_atendimento
    JOIN SGA_PACIENTE Pac ON PA.id_paciente = Pac.id_paciente
    JOIN SGA_PESSOA Pess ON Pac.NIF = Pess.NIF
    WHERE A.estado != 'cancelado'
    """
    
    #TODO: nao esquecer de experimentar descomentar isto
    # Se quiseres que o médico só veja as suas, podes descomentar e adaptar:
    # query += " AND EXISTS (SELECT 1 FROM SGA_TRABALHADOR_ATENDIMENTO TA WHERE TA.num_atendimento = A.num_atendimento AND TA.id_trabalhador = ?)"
    # cursor.execute(query, (session['user_id'],))
    
    cursor.execute(query)
    rows = cursor.fetchall()
    conn.close()
    
    eventos = []
    for row in rows:
        # Formata para o padrão do FullCalendar
        eventos.append({
            'title': row[1],             # Nome do Paciente (ex: "Ana Silva")
            'start': row[2].isoformat(), # Data Inicio (ISO 8601)
            'end': row[3].isoformat(),   # Data Fim
            # Cor: Verde se finalizado, Azul se agendado, Vermelho se falta
            'color': '#198754' if row[4] == 'finalizado' else ('#dc3545' if row[4] == 'falta' else '#0d6efd')
        })
        
    return jsonify(eventos)

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

@app.route('/')
@app.route('/dashboard')
def dashboard():
    if not is_logged_in(): return redirect(url_for('login'))

    conn = get_db_connection()
    cursor = conn.cursor()

    try: 
        total_p = contar_pacientes(cursor)
        total_pendentes = contar_pedidos_pendentes(cursor)
        consultas_hoje = contar_atendimentos_hoje(cursor)
        salas_livres = contar_salas_livres(cursor)

    except Exception as e:
        print(f"Erro: {e}")
        total_p = 0
        total_pendentes = 0
        consultas_hoje = {'total': 0, 'online': 0, 'presencial': 0}
        salas_livres = 0
    finally:
        cursor.close()
        conn.close()

    return render_template('dashboard.html',
                           nome_user=session.get('user_name'),
                           total_pacientes=total_p, total_pedidos=total_pendentes, consultas=consultas_hoje,
                           salas_livres=salas_livres)


if __name__ == '__main__':
    app.run(debug=True)
