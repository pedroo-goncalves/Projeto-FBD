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
    """
    Lista eventos para o calendário usando a Stored Procedure sp_listarEventosCalendario.
    """
    try:
        f_medico = filtro_medico_id if filtro_medico_id else None
        f_paciente = filtro_paciente_nif if filtro_paciente_nif else None

        cursor.execute("EXEC sp_listarEventosCalendario ?, ?, ?, ?", 
                       (user_id, perfil, f_medico, f_paciente))
        
        return cursor.fetchall()
        
    except Exception as e:
        print(f"Erro ao listar eventos do calendário: {e}")
        return []


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