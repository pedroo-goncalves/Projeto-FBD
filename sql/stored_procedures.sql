-- Template from: https://learn.microsoft.com/en-us/sql/relational-databases/stored-procedures/create-a-stored-procedure?view=sql-server-ver17

CREATE OR ALTER PROCEDURE sp_guardarPessoa
    @NIF CHAR(9),
    @nome VARCHAR(50),
    @data_nascimento DATE,
    @telefone CHAR(9),
    @email VARCHAR(100) = NULL
AS
/*
-- =============================================
-- Author:      Bernardo Santos
-- Create Date: 16/12/2025
-- Description: Upsert da pessoa
-- =============================================
*/
BEGIN
    SET NOCOUNT ON;
    IF LEN(@NIF) <> 9 OR @NIF LIKE '%[^0-9]%'
        THROW 50001, 'NIF invlido.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
            MERGE SGA_PESSOA AS target
            USING (SELECT @NIF, @nome, @data_nascimento, @telefone, @email) 
               AS source (NIF, nome, data_nascimento, telefone, email)
            ON (target.NIF = source.NIF)
            WHEN MATCHED THEN
                UPDATE SET nome = source.nome, data_nascimento = source.data_nascimento, telefone = source.telefone, email = source.email
            WHEN NOT MATCHED THEN
                INSERT (NIF, nome, data_nascimento, telefone, email)
                VALUES (source.NIF, source.nome, source.data_nascimento, source.telefone, source.email);
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_inserirPaciente
    @NIF CHAR(9),
    @data_inscricao DATE,
    @observacoes VARCHAR(250) = NULL,
    @id_medico_responsavel INT = NULL,
    @id_paciente INT OUTPUT
AS
/*
-- =============================================
-- Author:      Bernardo Santos
-- Create Date: 16/12/2025
-- Description: Insere um paciente
-- =============================================
*/
BEGIN
    SET NOCOUNT ON;
    -- VERIFICAÇÕES ORIGINAIS DO BERNARDO
    IF NOT EXISTS (SELECT 1 FROM SGA_PESSOA WHERE NIF = @NIF)
        THROW 50002, 'Pessoa nao encontrada.', 1;

    IF EXISTS (SELECT 1 FROM SGA_PACIENTE WHERE NIF = @NIF)
        THROW 50003, 'Paciente ja existe.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
            INSERT INTO SGA_PACIENTE (NIF, data_inscricao, observacoes)
            VALUES (@NIF, @data_inscricao, @observacoes);

            SET @id_paciente = SCOPE_IDENTITY();

            IF @id_medico_responsavel IS NOT NULL
                INSERT INTO SGA_VINCULO_CLINICO (id_trabalhador, id_paciente)
                VALUES (@id_medico_responsavel, @id_paciente);
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_atualizarObservacoesPaciente
    @id INT,
    @obs VARCHAR(250)
AS
/*
-- =============================================
-- Author:      Bernardo Santos
-- Create Date: 16/12/2025
-- Description: Atualiza as observacoes do paciente
--              com o respetivo id.
-- =============================================
*/
BEGIN
    SET NOCOUNT ON;
    -- verificar se existe paciente com esse id
    IF NOT EXISTS (SELECT 1 FROM SGA_PACIENTE WHERE id_paciente = @id)
        THROW 50004, 'N�o existe paciente com esse Id.', 1;

    BEGIN TRY
        UPDATE SGA_PACIENTE
            SET observacoes = @obs
            WHERE id_paciente = @id;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_obterLogin
    @NIF CHAR(9)
AS
/*
-- =============================================
-- Author:      Pedro Gonçalves
-- Create Date: 18/12/2025
-- Description: Obter os dados do login
-- =============================================
*/
BEGIN
    SET NOCOUNT ON;
    -- Usamos TRIM para remover espaços acidentais e garantir a comparação
    SELECT 
        T.id_trabalhador, 
        T.senha_hash, 
        T.tipo_perfil, 
        P.nome 
    FROM SGA_TRABALHADOR T
    JOIN SGA_PESSOA P ON T.NIF = P.NIF
    WHERE TRIM(T.NIF) = TRIM(@NIF) AND T.ativo = 1;
END
GO

CREATE OR ALTER PROCEDURE sp_listarMeusPacientes
    @id_medico INT
AS

/*
-- =============================================
-- Author:      Pedro Gonçalves
-- Create Date: 18/12/2025
-- Description: Listar os pacientes do médico do login,
--              ordena tudo por ordem de inserção mais recente.
-- =============================================
*/
BEGIN
    SET NOCOUNT ON;

    SELECT 
        P.nome, 
        P.NIF, 
        Pac.observacoes, 
        Pac.data_inscricao
    FROM SGA_PACIENTE Pac 
    JOIN SGA_PESSOA P ON Pac.NIF = P.NIF
    JOIN SGA_VINCULO_CLINICO V ON Pac.id_paciente = V.id_paciente
    WHERE V.id_trabalhador = @id_medico 
    ORDER BY Pac.data_inscricao DESC; 
END
GO

CREATE OR ALTER PROCEDURE sp_listarRelatoriosVinculados
    @id_trabalhador INT
AS
/*
-- ==========================================================
-- Autor:       Pedro Gonçalves
-- Create Date: 18/12/2025
-- Descrição:   Lista os relatórios que o trabalhador tem permissão
--              para ver (baseado nos seus vínculos clínicos).
-- ==========================================================
*/
BEGIN
    SET NOCOUNT ON;

    SELECT 
        R.id, 
        P_Paciente.nome AS paciente_nome, 
        R.data_criacao, 
        R.tipo_relatorio, 
        P_Autor.nome AS autor_nome
    FROM SGA_RELATORIO R
    JOIN SGA_PACIENTE Pac ON R.id_paciente = Pac.id_paciente
    JOIN SGA_PESSOA P_Paciente ON Pac.NIF = P_Paciente.NIF
    JOIN SGA_TRABALHADOR T_Autor ON R.id_autor = T_Autor.id_trabalhador
    JOIN SGA_PESSOA P_Autor ON T_Autor.NIF = P_Autor.NIF
    JOIN SGA_VINCULO_CLINICO V ON R.id_paciente = V.id_paciente
    WHERE V.id_trabalhador = @id_trabalhador 
    ORDER BY R.data_criacao DESC;
END
GO