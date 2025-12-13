import os
from dotenv import load_dotenv
import pyodbc

load_dotenv()

def get_db_connection():
    """
    Cria conexão ao SQL Server.
    """
    conn_str = (
        f'DRIVER={{ODBC Driver 17 for SQL Server}};'
        f'SERVER={os.getenv("SERVER")};'
        f'DATABASE={os.getenv("DATABASE")};'
        f'UID={os.getenv("UID")};'
        f'PWD={os.getenv("PWD")};'
    )
    return pyodbc.connect(conn_str)

def test_connection():
    try:
        conn = get_db_connection()
        print("Conexão realizada com sucesso.")
        return True
    except Exception as e:
        print("Erro na conexão.")
        return False
    
if __name__ == "__main__":
    print("A testar a conexão...")
    test_connection()