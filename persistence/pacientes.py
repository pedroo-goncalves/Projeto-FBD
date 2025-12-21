from datetime import datetime

def contar_pacientes(cursor):
    try:
        cursor.execute("exec sp_countPaciente")

        row = cursor.fetchone()
        if row:
            # isto e o valor count
            return row[0]
        return 0
    except Exception as e:
        print(f"Erro a contar Pacientes: {e}")
        return 0
    
def criar_paciente_via_agenda(cursor, nif, nome, telemovel, data_nasc):
    """
    Chama a SP Mestra que trata de Pessoa + Paciente numa transação atómica.
    """
    # Bloco T-SQL para capturar o output
    query = """
        DECLARE @id_out INT;
        
        EXEC sp_RegistoRapidoAgenda 
            @nif = ?, 
            @nome = ?, 
            @telemovel = ?, 
            @data_nasc = ?, 
            @id_paciente_gerado = @id_out OUTPUT;
        
        SELECT @id_out AS id_gerado;
    """
    
    cursor.execute(query, (nif, nome, telemovel, data_nasc))
    
    row = cursor.fetchone()
    return row[0] if row else None

def listar_pacientes_geral(cursor, id_user, perfil):
    """Substitui a query da rota /pacientes"""
    cursor.execute("EXEC sp_listarPacientesSGA ?, ?", (id_user, perfil))
    return cursor.fetchall() # Retorna tuplos, como o template espera

def listar_pacientes_arquivo(cursor):
    cursor.execute("EXEC sp_listarPacientesInativos")
    return cursor.fetchall()

def listar_pacientes_dropdown_agenda(cursor, id_user, perfil):
    """Substitui a lógica da rota /agenda para pacientes"""
    cursor.execute("EXEC sp_ListarPacientesParaAgenda ?, ?", (id_user, perfil))
    rows = cursor.fetchall()
    # REPLICAÇÃO EXATA DA LÓGICA DO APP.PY:
    return [{'nif': r[2], 'nome': r[1]} for r in rows]

def criar_paciente_completo(cursor, nif, nome, data_nasc, telefone, email, observacoes, id_medico):
    cursor.execute("EXEC sp_guardarPessoa ?, ?, ?, ?, ?", 
                   (nif, nome, data_nasc, telefone, email))
    
    data_hoje = datetime.now().date()
    cursor.execute("EXEC sp_inserirPaciente ?, ?, ?, ?", 
                   (nif, data_hoje, observacoes, id_medico))

def obter_detalhes_paciente(cursor, id_paciente, id_user, perfil):
    cursor.execute("EXEC sp_obterFichaCompletaPaciente ?, ?, ?", (id_paciente, id_user, perfil))
    return cursor.fetchone()

def atualizar_observacoes_paciente(cursor, id_paciente, obs):
    cursor.execute("EXEC sp_atualizarObservacoesPaciente @id=?, @obs=?", (id_paciente, obs))

def editar_dados_paciente(cursor, nif, nome, telefone, email, observacoes):
    cursor.execute("EXEC sp_editarPaciente ?, ?, ?, ?, ?", 
                   (nif, nome, telefone, email, observacoes))

def desativar_paciente_logico(cursor, id_paciente):
    cursor.execute("EXEC sp_desativarPaciente ?", (id_paciente,))

def ativar_paciente_logico(cursor, id_paciente):
    # Nota: No teu app.py estava um UPDATE direto. 
    # Se tens a SP sp_ativarPaciente, usamos ela. Se não, mantemos o UPDATE.
    # O teu ficheiro stored_procedures.sql TEM a sp_ativarPaciente. Vamos usá-la.
    cursor.execute("EXEC sp_ativarPaciente ?", (id_paciente,))

def eliminar_paciente_fisico(cursor, id_paciente):
    cursor.execute("EXEC sp_eliminarPacientePermanente ?", (id_paciente,))