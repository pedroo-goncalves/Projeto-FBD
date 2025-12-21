SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER FUNCTION udf_VerificarColisaoMedico
(
    @id_medico INT,
    @data_inicio DATETIME2,
    @duracao INT,
    @ignorar_atendimento_id INT = NULL
)
RETURNS BIT
AS
BEGIN
    DECLARE @colisao BIT = 0;
    DECLARE @data_fim DATETIME2 = DATEADD(MINUTE, @duracao, @data_inicio);

    IF EXISTS (
        SELECT 1 
        FROM SGA_TRABALHADOR_ATENDIMENTO ta
        JOIN SGA_ATENDIMENTO a ON ta.num_atendimento = a.num_atendimento
        WHERE ta.id_trabalhador = @id_medico 
          AND a.estado != 'cancelado'
          AND (@ignorar_atendimento_id IS NULL OR a.num_atendimento != @ignorar_atendimento_id)
          AND (
              (@data_inicio >= a.data_inicio AND @data_inicio < a.data_fim)
              OR 
              (@data_fim > a.data_inicio AND @data_fim <= a.data_fim)
              OR
              (@data_inicio <= a.data_inicio AND @data_fim >= a.data_fim)
          )
    )
    BEGIN
        SET @colisao = 1;
    END

    RETURN @colisao;
END
GO

CREATE OR ALTER FUNCTION udf_ContarEquipaAtiva()
RETURNS INT
AS
BEGIN
    RETURN (SELECT COUNT(*) FROM SGA_TRABALHADOR WHERE ativo = 1);
END
GO

CREATE OR ALTER FUNCTION udf_ContarPacientesAtivos()
RETURNS INT
AS
BEGIN
    RETURN (SELECT COUNT(*) FROM SGA_PACIENTE WHERE ativo = 1);
END
GO