# persistence/dashboard.py
from datetime import datetime

def obter_totais_dashboard(cursor, user_id, perfil):
    """
    Retorna um dicionário com: total_pacientes, total_equipa, consultas_hoje
    """
    try:
        cursor.execute("EXEC sp_ObterDashboardTotais ?, ?", (user_id, perfil))
        row = cursor.fetchone()
        
        if row:
            return {
                'total_pacientes': row[0],
                'total_equipa': row[1],
                'consultas_hoje': row[2]
            }
        return {'total_pacientes': 0, 'total_equipa': 0, 'consultas_hoje': 0}
    except Exception as e:
        print(f"Erro ao obter totais dashboard: {e}")
        return {'total_pacientes': 0, 'total_equipa': 0, 'consultas_hoje': 0}

def listar_proximas_consultas(cursor, user_id, perfil):
    """
    Retorna lista de dicionários com as próximas 5 consultas
    """
    try:
        cursor.execute("EXEC sp_ObterProximasConsultas ?, ?", (user_id, perfil))
        rows = cursor.fetchall()
        
        consultas = []
        for row in rows:
            # row[2] é datetime do SQL Server
            data_obj = row[2]
            
            consultas.append({
                'id': row[0],
                'paciente': row[1],
                'hora': data_obj.strftime('%H:%M'),
                'dia': data_obj.strftime('%d/%m'),
                'dia_iso': data_obj.strftime('%Y-%m-%d'),
                'estado': row[3],
                'medico': row[4]
            })
        return consultas
    except Exception as e:
        print(f"Erro ao listar próximas consultas: {e}")
        return []