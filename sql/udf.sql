-- =========================================================================================
-- FICHEIRO: 03_funcoes.sql
-- DESCRIÇÃO: Funções escalares para validações e cálculos
-- =========================================================================================
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- 1. Verificar Colisão de Horário Médico (Refatoração da lógica da Agenda)
CREATE OR ALTER FUNCTION udf_VerificarColisaoMedico
(
    @id_medico INT,
    @data_inicio DATETIME2,
    @duracao INT, -- em minutos
    @ignorar_atendimento_id INT = NULL -- Para usar na edição
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
          -- Ignorar o próprio agendamento se estivermos a editar
          AND (@ignorar_atendimento_id IS NULL OR a.num_atendimento != @ignorar_atendimento_id)
          AND (
              -- Lógica de sobreposição de tempo
              (@data_inicio >= a.data_inicio AND @data_inicio < a.data_fim) -- Começa durante
              OR 
              (@data_fim > a.data_inicio AND @data_fim <= a.data_fim) -- Termina durante
              OR
              (@data_inicio <= a.data_inicio AND @data_fim >= a.data_fim) -- Engloba
          )
    )
    BEGIN
        SET @colisao = 1;
    END

    RETURN @colisao;
END
GO

-- 2. Contadores auxiliares (Já tinhas estes, mas formalizamos aqui)
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