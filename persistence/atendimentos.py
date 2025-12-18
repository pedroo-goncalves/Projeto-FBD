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