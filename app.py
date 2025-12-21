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
        
        hash_introduzido = hashlib.sha256(senha.encode()).hexdigest()
        try:
            conn = get_db_connection()
            cursor = conn.cursor()
            cursor.execute("EXEC sp_obterLogin ?", (nif,))
            user = cursor.fetchone()
            conn.close()

            # user[0]=ID, user[1]=Hash, user[2]=Perfil, user[3]=Nome, user[4]=NIF (Adicionar à SP)
            if user and hash_introduzido == user[1]:
                # IMPORTANTE: Vamos guardar o NIF na sessão para as Procedures de vínculo
                # Precisas que a sp_obterLogin devolva o NIF como 5º campo (user[4])
                session['user_id'] = nif  # Agora a 'user_id' guarda o NIF!
                session['user_id_interno'] = user[0] # Guardamos o ID numérico para a Agenda
                session['user_name'] = user[3]
                session['perfil'] = user[2]
                return redirect(url_for('dashboard'))
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
    if 'user_id' not in session: return redirect(url_for('login'))
    
    nif_user = session.get('user_id')  # O NIF de quem está logado
    perfil = session.get('perfil')     # 'admin' ou 'colaborador'

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # 1. LISTA DE PACIENTES: A SP decide o que mostrar com base no perfil
        cursor.execute("EXEC sp_listarPacientesSGA ?, ?", (nif_user, perfil))
        lista_pacientes = cursor.fetchall()
        
        # 2. LISTA DE EQUIPA: Para o Modal de atribuição
        cursor.execute("EXEC sp_listarEquipa")
        lista_trabalhadores = cursor.fetchall()
        
        conn.close()
        
        return render_template('pacientes.html', 
                               pacientes=lista_pacientes, 
                               trabalhadores=lista_trabalhadores, 
                               nome_user=session.get('user_name'))
                               
    except Exception as e:
        flash(f"Erro ao carregar dados: {e}", "danger")
        return redirect(url_for('dashboard'))


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
    nif = request.form.get('nif')
    nome = request.form.get('nome')
    data_nasc = request.form.get('data_nasc')
    email = request.form.get('email')
    telefone = request.form.get('telefone')
    observacoes = request.form.get('observacoes')
    nif_medico = request.form.get('id_medico') # No HTML, isto agora é o NIF

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # 1. Cria ou Atualiza a Pessoa
        cursor.execute("EXEC sp_guardarPessoa ?, ?, ?, ?, ?", 
                       (nif, nome, data_nasc, telefone, email))
        
        # 2. Cria o Paciente e o Vínculo por NIF
        cursor.execute("EXEC sp_inserirPaciente ?, ?, ?, ?", 
                       (nif, datetime.now().date(), observacoes, nif_medico))
        
        conn.commit()
        conn.close()
        flash("Paciente registado e associado com sucesso!", "success")
    except Exception as e:
        flash(f"Erro ao criar: {e}", "danger")
        
    return redirect(url_for('pacientes'))

@app.route('/pacientes/detalhes/<int:id_paciente>')
def pacientes_detalhes(id_paciente):
    if 'user_id' not in session: return redirect(url_for('login'))
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        # 1. Dados do Paciente
        cursor.execute("EXEC sp_obterFichaCompletaPaciente ?, ?, ?", (id_paciente, session['user_id'], session['perfil']))
        detalhes = cursor.fetchone()

        # 2. LISTA DE EQUIPA RESPONSÁVEL (NOVO)
        cursor.execute("EXEC sp_listarTrabalhadoresDePaciente ?", (id_paciente,))
        equipa_vinculada = cursor.fetchall()

        conn.close()
        return render_template('pacientes_detalhes.html', p=detalhes, equipa=equipa_vinculada, nome_user=session['user_name'])
    except Exception as e:
        flash(f"Erro: {e}", "danger")
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

@app.route('/pacientes/eliminar/<int:id_paciente>', methods=['POST'])
def eliminar_paciente(id_paciente):
    if session.get('perfil') != 'admin': return redirect(url_for('dashboard'))
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_eliminarPacientePermanente ?", (id_paciente,))
        conn.commit()
        conn.close()
        flash("Paciente e dados associados eliminados com sucesso.", "success")
    except Exception as e:
        flash(f"{e}", "danger")
    
    # REDIRECIONAMENTO CORRETO para o nome da função que tens na linha 144
    return redirect(url_for('pacientes_arquivo'))
# ------------------------------------------------------------------
# ROTA 5: RELATÓRIOS
# ------------------------------------------------------------------
# ------------------------------------------------------------------
# ROTAS DE RELATÓRIOS (SISTEMA DE LIVRARIA CLÍNICA)
# ------------------------------------------------------------------

@app.route('/relatorios')
def relatorios():
    if 'user_id' not in session: return redirect(url_for('login'))
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # CORREÇÃO: Usar o nome da Procedure certa e passar os 2 argumentos que ela pede
        # Se a sp_listarProcessosClinicosAtivos pede um INT, usa user_id_interno
        cursor.execute("EXEC sp_listarProcessosClinicosAtivos ?, ?", 
                       (session['user_id_interno'], session['perfil']))
        
        lista = cursor.fetchall()
        conn.close()
        return render_template('relatorios.html', relatorios=lista, nome_user=session['user_name'])
    except Exception as e:
        # Se der erro, ele imprime no terminal para conseguires depurar
        print(f"Erro na rota relatorios: {e}")
        flash(f"Erro ao carregar processos: {e}", "danger")
        return redirect(url_for('dashboard'))

@app.route('/relatorios/detalhes/<int:id_paciente>')
def detalhes_relatorio_unificado(id_paciente):
    if 'user_id' not in session: return redirect(url_for('login'))
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # Busca o nome do paciente para o cabeçalho (SQL Puro)
    cursor.execute("SELECT Pe.nome FROM SGA_PACIENTE Pa JOIN SGA_PESSOA Pe ON Pa.NIF = Pe.NIF WHERE Pa.id_paciente = ?", (id_paciente,))
    res = cursor.fetchone()
    nome_p = res[0] if res else "Paciente"

    # Carrega a livraria de capítulos
    cursor.execute("EXEC sp_obterLivrariaRelatorios ?, ?", (id_paciente, session['user_id_interno']))
    notas = cursor.fetchall()
    conn.close()
    return render_template('relatorio_detalhes.html', paciente_id=id_paciente, nome_p=nome_p, notas=notas, nome_user=session['user_name'])

@app.route('/relatorios/salvar', methods=['POST'])
def salvar_relatorio():
    # Se id_relatorio estiver vazio no formulário, o SQL faz INSERT automático
    id_rel = request.form.get('id_relatorio')
    id_pac = request.form.get('id_paciente')
    tipo = request.form.get('tipo')
    conteudo = request.form.get('conteudo')
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_salvarRelatorioClinico ?, ?, ?, ?, ?", 
                       (id_rel if id_rel else None, id_pac, session['user_id_interno'], conteudo, tipo))
        conn.commit()
        conn.close()
        flash("Processo clínico atualizado.", "success")
    except Exception as e:
        flash(f"Erro ao gravar: {e}", "danger")

    # REDIRECIONAMENTO: Mantém o médico na livraria do paciente
    return redirect(url_for('detalhes_relatorio_unificado', id_paciente=id_pac))

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

@app.route('/equipa/eliminar/<int:id_trabalhador>', methods=['POST'])
def eliminar_trabalhador(id_trabalhador):
    if session.get('perfil') != 'admin': return redirect(url_for('dashboard'))
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_eliminarTrabalhadorPermanente ?", (id_trabalhador,))
        conn.commit()
        conn.close()
        flash("Funcionário removido permanentemente.", "success")
    except Exception as e:
        flash(f"{e}", "danger")
    
    # REDIRECIONAMENTO CORRETO para o nome da função que tens na linha 311
    return redirect(url_for('equipa_arquivo'))

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
        # 1. Dados do Trabalhador
        cursor.execute("EXEC sp_obterDetalhesTrabalhador ?, ?", (id_trabalhador, session['perfil']))
        trabalhador = cursor.fetchone()
        
        # 2. LISTA DE PACIENTES (NOVO)
        cursor.execute("EXEC sp_listarPacientesDeTrabalhador ?", (id_trabalhador,))
        pacientes_vinculados = cursor.fetchall()
        
        conn.close()
        return render_template('equipa_detalhes.html', t=trabalhador, pacientes=pacientes_vinculados, nome_user=session['user_name'])
    except Exception as e:
        flash(f"Erro: {e}", "danger")
        return redirect(url_for('equipa'))



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

@app.route('/admin/editar_trabalhador_post', methods=['POST'])
def editar_trabalhador_post():
    if session.get('perfil') != 'admin': return redirect(url_for('equipa'))
    
    nif = request.form.get('nif')
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_editarTrabalhador ?, ?, ?, ?, ?, ?, ?, ?", 
            (nif, request.form.get('nome'), request.form.get('telefone'),
             request.form.get('email'), request.form.get('perfil'),
             request.form.get('cedula'), request.form.get('categoria'),
             request.form.get('campo_extra')))
        conn.commit()
        conn.close()
        flash("Dados do funcionário atualizados!", "success")
    except Exception as e:
        flash(f"Erro ao editar: {e}", "danger")
    
    # Retorna para os detalhes do trabalhador editado
    return redirect(request.referrer)

@app.route('/admin/editar_paciente_post', methods=['POST'])
def editar_paciente_post():
    if session.get('perfil') != 'admin': return redirect(url_for('pacientes'))
    
    nif = request.form.get('nif')
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_editarPaciente ?, ?, ?, ?, ?", 
            (nif, request.form.get('nome'), request.form.get('telefone'),
             request.form.get('email'), request.form.get('observacoes')))
        conn.commit()
        conn.close()
        flash("Ficha do paciente atualizada!", "success")
    except Exception as e:
        flash(f"Erro ao editar: {e}", "danger")
    
    return redirect(request.referrer)

if __name__ == '__main__':
    app.run(debug=True)
