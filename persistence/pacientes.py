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