CREATE PROCEDURE sp_guardarPessoa
    @NIF CHAR(9),
    @nome VARCHAR(50),
    @data_nascimento DATE,
    @telefone CHAR(9)
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
        THROW 50001, 'NIF inv�lido.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

            MERGE SGA_PESSOA AS target
            USING (
                SELECT 
                    @NIF AS NIF, 
                    @nome AS nome, 
                    @data_nascimento AS data_nascimento, 
                    @telefone AS telefone
            ) AS source
            ON (target.NIF = source.NIF)
            
            WHEN MATCHED THEN
                UPDATE SET 
                    nome = source.nome,
                    data_nascimento = source.data_nascimento,
                    telefone = source.telefone
            
            WHEN NOT MATCHED THEN
                INSERT (NIF, nome, data_nascimento, telefone)
                VALUES (source.NIF, source.nome, source.data_nascimento, source.telefone);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE PROCEDURE sp_inserirPaciente
    @NIF CHAR(9),
    @data_inscricao DATE,
    @observacoes VARCHAR(250) = NULL,

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

    -- verificar se existe pessoa com esse nif
    IF NOT EXISTS (SELECT 1 FROM SGA_PESSOA WHERE NIF = @NIF)
        THROW 50002, 'Pessoa n�o encontrada.', 1;

    -- verficar se existe paciente com esse nif
    IF EXISTS (SELECT 1 FROM SGA_PACIENTE WHERE NIF = @NIF)
        THROW 50003, 'Paciente ja existe.', 1;

    INSERT INTO SGA_PACIENTE (NIF, data_inscricao, observacoes)
    VALUES (@NIF, @data_inscricao, @observacoes);

    SET @id_paciente = SCOPE_IDENTITY();
END
GO

CREATE PROCEDURE sp_atualizarObservacoesPaciente
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
