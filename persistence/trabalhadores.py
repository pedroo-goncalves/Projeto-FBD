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
