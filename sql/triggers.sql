-- =========================================================================================
-- FICHEIRO: 06_triggers.sql
-- DESCRIÇÃO: Triggers para automação de regras de negócio
-- =========================================================================================
CREATE OR ALTER TRIGGER trg_DesativarTrabalhador
ON SGA_TRABALHADOR
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Se o estado mudou para inativo (0) e a data_fim ainda é NULL, preenche automaticamente
    IF UPDATE(ativo)
    BEGIN
        UPDATE T
        SET data_fim = GETDATE()
        FROM SGA_TRABALHADOR T
        INNER JOIN inserted i ON T.id_trabalhador = i.id_trabalhador
        INNER JOIN deleted d ON T.id_trabalhador = d.id_trabalhador
        WHERE i.ativo = 0 AND d.ativo = 1 AND T.data_fim IS NULL;
    END
END
GO