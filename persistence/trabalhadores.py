def medicos_agenda_dropdown(cursor):
    try:
        cursor.execute('exec sp_listarMedicosAgenda')
        rows = cursor.fetchall()
        if rows:
            return [{'id':row[0], 'nome':row[1]} for row in rows]
        return []
    except Exception as e:
        print(f"erro a listar tabalhadores: {e}")
        return []

def obter_dados_login(cursor, nif):
    """Retorna (id, hash, perfil, nome) ou None"""
    try:
        cursor.execute("EXEC sp_obterLogin ?", (nif,))
        return cursor.fetchone()
    except Exception as e:
        print(f"Erro no login DB: {e}")
        return None
    
def obter_nome_trabalhador(cursor, id_user):
    cursor.execute("SELECT nome FROM SGA_PESSOA p JOIN SGA_TRABALHADOR t ON p.NIF = t.NIF WHERE t.id_trabalhador = ?", (id_user,))
    res = cursor.fetchone()
    return res[0] if res else 'Utilizador'

def listar_equipa_ativa(cursor):
    cursor.execute("EXEC sp_listarEquipa")
    return cursor.fetchall() # Tuplos para o equipa.html

def listar_equipa_arquivo(cursor):
    cursor.execute("EXEC sp_listarEquipaInativa")
    return cursor.fetchall()

def obter_perfil_trabalhador(cursor, id_alvo, perfil_solicitante):
    cursor.execute("EXEC sp_obterDetalhesTrabalhador ?, ?", (id_alvo, perfil_solicitante))
    return cursor.fetchone()

def listar_pacientes_do_medico(cursor, id_medico):
    cursor.execute("EXEC sp_listarPacientesDeTrabalhador ?", (id_medico,))
    return cursor.fetchall()

def listar_equipa_do_paciente(cursor, id_paciente):
    cursor.execute("EXEC sp_listarTrabalhadoresDePaciente ?", (id_paciente,))
    return cursor.fetchall()

# FUNÇÃO ESPECÍFICA PARA O MODAL DE PACIENTES
# O template pacientes.html espera 'id_trabalhador'
def listar_medicos_para_modal_pacientes(cursor):
    cursor.execute("EXEC sp_listarMedicosAgenda")
    rows = cursor.fetchall()
    # REPLICAÇÃO EXATA DA LÓGICA DO APP.PY (linha 106 do upload anterior)
    return [{'id_trabalhador': r[0], 'nome': r[1]} for r in rows]

def criar_novo_funcionario(cursor, nif, nome, data_nasc, telemovel, email, senha_hash, perfil, cedula, categoria, contrato, ordem, remuneracao):
    cursor.execute("EXEC sp_criarFuncionario ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?", 
                   (nif, nome, data_nasc, telemovel, email, senha_hash, 
                    perfil, cedula, categoria, contrato, ordem, remuneracao))

def editar_ficha_trabalhador(cursor, nif, nome, telefone, email, perfil, cedula, categoria, extra):
    cursor.execute("EXEC sp_editarTrabalhador ?, ?, ?, ?, ?, ?, ?, ?", 
                   (nif, nome, telefone, email, perfil, cedula, categoria, extra))

def desativar_trabalhador(cursor, id_trabalhador):
    cursor.execute("EXEC sp_desativarFuncionario ?", (id_trabalhador,))

def ativar_trabalhador(cursor, id_trabalhador):
    cursor.execute("EXEC sp_ativarFuncionario ?", (id_trabalhador,))

def eliminar_trabalhador_fisico(cursor, id_trabalhador):
    cursor.execute("EXEC sp_eliminarTrabalhadorPermanente ?", (id_trabalhador,))