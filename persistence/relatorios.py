def listar_relatorios_dashboard(cursor, id_user, perfil):
    cursor.execute("EXEC sp_listarProcessosClinicosAtivos ?, ?", (id_user, perfil))
    return cursor.fetchall()

def carregar_historico_relatorios(cursor, id_paciente, id_leitor):
    cursor.execute("EXEC sp_obterLivrariaRelatorios ?, ?", (id_paciente, id_leitor))
    return cursor.fetchall()

def obter_nome_paciente_simples(cursor, id_paciente):
    # Query direta que estava no app.py
    cursor.execute("SELECT Pe.nome FROM SGA_PACIENTE Pa JOIN SGA_PESSOA Pe ON Pa.NIF = Pe.NIF WHERE Pa.id_paciente = ?", (id_paciente,))
    res = cursor.fetchone()
    return res[0] if res else "Paciente"

def guardar_relatorio_clinico(cursor, id_rel, id_pac, id_autor, conteudo, tipo):
    cursor.execute("EXEC sp_salvarRelatorioClinico ?, ?, ?, ?, ?", 
                   (id_rel, id_pac, id_autor, conteudo, tipo))