-- =========================================================================================
-- FICHEIRO: 04_indices.sql
-- DESCRIÇÃO: Índices Non-Clustered para otimização (Verifica existência antes de criar)
-- =========================================================================================

-- 1. Otimizar a Agenda (Pesquisas por data e estado)
IF NOT EXISTS (SELECT name FROM sys.indexes WHERE name = N'IX_Atendimento_Data_Estado' AND object_id = OBJECT_ID(N'SGA_ATENDIMENTO'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_Atendimento_Data_Estado 
    ON SGA_ATENDIMENTO (data_inicio, data_fim, estado)
    INCLUDE (id_sala);
END
GO

-- 2. Otimizar as pesquisas de Vínculos Clínicos (Listagem de Pacientes do Médico)
IF NOT EXISTS (SELECT name FROM sys.indexes WHERE name = N'IX_Vinculo_Trabalhador' AND object_id = OBJECT_ID(N'SGA_VINCULO_CLINICO'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_Vinculo_Trabalhador
    ON SGA_VINCULO_CLINICO (NIF_trabalhador)
    INCLUDE (NIF_paciente);
END
GO

-- 3. Otimizar a junção Pessoa-Trabalhador (Login e Listagens de Equipa)
IF NOT EXISTS (SELECT name FROM sys.indexes WHERE name = N'IX_Trabalhador_NIF' AND object_id = OBJECT_ID(N'SGA_TRABALHADOR'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_Trabalhador_NIF
    ON SGA_TRABALHADOR (NIF)
    INCLUDE (id_trabalhador, tipo_perfil, ativo);
END
GO

-- 4. Otimizar a junção Pessoa-Paciente (Pesquisas de Pacientes)
IF NOT EXISTS (SELECT name FROM sys.indexes WHERE name = N'IX_Paciente_NIF' AND object_id = OBJECT_ID(N'SGA_PACIENTE'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_Paciente_NIF
    ON SGA_PACIENTE (NIF)
    INCLUDE (id_paciente, ativo);
END
GO