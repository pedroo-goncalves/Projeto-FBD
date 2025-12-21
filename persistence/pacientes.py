from datetime import datetime

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
    
def criar_paciente_via_agenda(cursor, nif, nome, telemovel, data_nasc):
    """
    Chama a SP Mestra que trata de Pessoa + Paciente numa transação atómica.
    """
    # Bloco T-SQL para capturar o output
    query = """
        DECLARE @id_out INT;
        
        EXEC sp_RegistoRapidoAgenda 
            @nif = ?, 
            @nome = ?, 
            @telemovel = ?, 
            @data_nasc = ?, 
            @id_paciente_gerado = @id_out OUTPUT;
        
        SELECT @id_out AS id_gerado;
    """
    
    cursor.execute(query, (nif, nome, telemovel, data_nasc))
    
    row = cursor.fetchone()
    return row[0] if row else None