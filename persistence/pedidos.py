def contar_pedidos_pendentes(cursor):
    try:
        cursor.execute("exec sp_countPedidosPendentes")
        count = cursor.fetchone()

        if count:
            return count[0]
        return 0
    except Exception as e:
        print(f"Erro a contar pedidos pendentes: {e}")
        return 0
    