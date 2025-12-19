def contar_salas_livres(cursor):
    try:
        cursor.execute("EXEC sp_contarSalasLivresAgora")
        row = cursor.fetchone()
        return row[0] if row else 0
    except Exception as e:
        print(f"Erro salas livres: {e}")
        return 0