CREATE OR ALTER TRIGGER trg_DesativarTrabalhador
ON SGA_TRABALHADOR
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

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