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
    """
    Lista eventos para o calendário.
    - Se perfil for 'colaborador': Vê apenas os agendamentos onde é o médico responsável.
    - Se perfil for 'admin': Vê a agenda de toda a clínica.
    """
    
    base_query = """
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
    """

    try:
        if perfil == 'colaborador':
            # so ver os seus atendimentos
            query = base_query + """
            JOIN SGA_TRABALHADOR_ATENDIMENTO TA ON A.num_atendimento = TA.num_atendimento
            WHERE A.estado != 'cancelado' 
              AND TA.id_trabalhador = ?
            """
            cursor.execute(query, (user_id,))
        else:
            query = base_query + " WHERE A.estado != 'cancelado'"
            cursor.execute(query)
            
        return cursor.fetchall()
        
    except Exception as e:
        print(f"Erro ao listar eventos: {e}")
        return []