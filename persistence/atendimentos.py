def contar_atendimentos_hoje(cursor):
    try:
        cursor.execute('exec sp_countConsultasHoje')
        row = cursor.fetchone()

        if row:
            presencial = row[0] - row[1]
            return {
                'total': row[0],
                'online': row[1],
                'presencial': presencial
            }
        return {'total': 0, 'online': 0, 'presencial': 0}
    except Exception as e:
        print(f"Erro a contar consultas: {e}")
        return {'total': 0, 'online': 0, 'presencial': 0}

def obter_horarios_livres(cursor, id_medico, data, is_online=0, duracao=60, ignorar_id=None):
    try:
        cursor.execute("EXEC sp_ObterHorariosLivres ?, ?, ?, ?, ?", 
                       (id_medico, data, is_online, duracao, ignorar_id))
        rows = cursor.fetchall()
        return [row[0] for row in rows]
    except Exception as e:
        print(f"Erro slots: {e}")
        return []
    
def listar_eventos_calendario(cursor, user_id, perfil, filtro_medico_id=None, filtro_paciente_nif=None):
    # Query Base
    query = """
    SELECT 
        A.num_atendimento,
        PessPac.nome AS NomePaciente,
        A.data_inicio,
        A.data_fim,
        A.estado,
        PessMed.nome AS NomeMedico
    FROM SGA_ATENDIMENTO A
    JOIN SGA_PACIENTE_ATENDIMENTO PA ON A.num_atendimento = PA.num_atendimento
    JOIN SGA_PACIENTE Pac ON PA.id_paciente = Pac.id_paciente
    JOIN SGA_PESSOA PessPac ON Pac.NIF = PessPac.NIF
    JOIN SGA_TRABALHADOR_ATENDIMENTO TA ON A.num_atendimento = TA.num_atendimento
    JOIN SGA_TRABALHADOR T ON TA.id_trabalhador = T.id_trabalhador
    JOIN SGA_PESSOA PessMed ON T.NIF = PessMed.NIF
    WHERE A.estado != 'cancelado'
    """
    
    params = []

    # 1. Regra de Segurança Base (Perfil)
    if perfil == 'colaborador':
        query += " AND TA.id_trabalhador = ?"
        params.append(user_id)
        # Nota: Se for colaborador, ignoramos o filtro_medico_id que vem do front-end
        # para garantir que ele não vê agenda de outros.
    
    # 2. Filtro de Médico (Apenas se for Admin)
    elif perfil == 'admin' and filtro_medico_id:
        query += " AND TA.id_trabalhador = ?"
        params.append(filtro_medico_id)

    # 3. Filtro de Paciente (Para todos)
    if filtro_paciente_nif:
        query += " AND PessPac.NIF = ?"
        params.append(filtro_paciente_nif)

    cursor.execute(query, params)
    return cursor.fetchall()


def obter_detalhes_atendimento(cursor, id_atendimento):
    try:
        cursor.execute("EXEC sp_obterDetalhesAtendimento ?", (id_atendimento,))
        row = cursor.fetchone()
        if row:
            # Calcula duração em minutos para preencher o form
            duracao = int((row[6] - row[5]).total_seconds() / 60)
            return {
                'id': row[0],
                'paciente': row[1],
                'nif_paciente': row[2],
                'medico': row[3],
                'id_medico': row[4],
                'inicio': row[5],
                'fim': row[6],
                'estado': row[7],
                'duracao': duracao
            }
        return None
    except Exception as e:
        print(f"Erro detalhes: {e}")
        return None

def editar_agendamento(cursor, id_atendimento, nova_data_str, duracao):
    # nova_data_str vem como 'YYYY-MM-DD HH:MM'
    cursor.execute("EXEC sp_editarAgendamento ?, ?, ?", (id_atendimento, nova_data_str, duracao))

def cancelar_agendamento(cursor, id_atendimento):
    cursor.execute("EXEC sp_cancelarAgendamento ?", (id_atendimento,))