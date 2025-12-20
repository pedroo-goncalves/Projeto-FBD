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

def obter_horarios_livres(cursor, id_medico, data):
    try:
        cursor.execute("EXEC sp_ObterHorariosLivres ?, ?", (id_medico, data))
        rows = cursor.fetchall()
        # Converte a lista de tuplos [('09:00',), ('10:00',)] numa lista simples
        return [row[0] for row in rows]
    except Exception as e:
        print(f"Erro slots: {e}")
        return []
    
def listar_eventos_calendario(cursor, user_id, perfil):
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
    -- Joins para saber o médico
    JOIN SGA_TRABALHADOR_ATENDIMENTO TA ON A.num_atendimento = TA.num_atendimento
    JOIN SGA_TRABALHADOR T ON TA.id_trabalhador = T.id_trabalhador
    JOIN SGA_PESSOA PessMed ON T.NIF = PessMed.NIF
    WHERE A.estado != 'cancelado'
    """

    if perfil == 'colaborador':
        query += " AND TA.id_trabalhador = ?"
        cursor.execute(query, (user_id,))
    else:
        cursor.execute(query)
            
    return cursor.fetchall()