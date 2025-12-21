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