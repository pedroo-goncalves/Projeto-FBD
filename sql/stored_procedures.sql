SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================
-- 1. GESTÃO DE UTILIZADORES E LOGIN
-- =============================================

CREATE OR ALTER PROCEDURE sp_obterLogin
    @NIF CHAR(9)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT 
        T.id_trabalhador, -- user[0]
        T.senha_hash,     -- user[1]
        T.tipo_perfil,    -- user[2]
        P.nome,           -- user[3]
        P.NIF             -- user[4] 
    FROM SGA_TRABALHADOR T
    JOIN SGA_PESSOA P ON T.NIF = P.NIF
    WHERE T.NIF = @NIF AND T.ativo = 1;
END
GO

CREATE OR ALTER PROCEDURE sp_guardarPessoa
    @NIF CHAR(9),
    @nome VARCHAR(50),
    @data_nascimento DATE,
    @telefone CHAR(9),
    @email VARCHAR(100) = NULL
AS
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

-- =============================================
-- 2. DASHBOARD E ESTATÍSTICAS
-- =============================================

CREATE OR ALTER PROCEDURE sp_ObterDashboardTotais
    @id_trabalhador INT,
    @perfil VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TotalPacientes INT;
    DECLARE @TotalEquipa INT = dbo.udf_ContarEquipaAtiva();
    DECLARE @ConsultasHoje INT;

    IF @perfil = 'admin'
    BEGIN
        SELECT @TotalPacientes = COUNT(*) FROM SGA_PACIENTE WHERE ativo = 1;
    END
    ELSE
    BEGIN
        DECLARE @NifMedico CHAR(9);
        SELECT @NifMedico = NIF FROM SGA_TRABALHADOR WHERE id_trabalhador = @id_trabalhador;

        SELECT @TotalPacientes = COUNT(DISTINCT v.NIF_paciente)
        FROM SGA_VINCULO_CLINICO v
        JOIN SGA_PACIENTE p ON v.NIF_paciente = p.NIF
        WHERE v.NIF_trabalhador = @NifMedico
          AND p.ativo = 1; 
    END

    IF @perfil = 'admin'
    BEGIN
        SELECT @ConsultasHoje = COUNT(*) 
        FROM SGA_ATENDIMENTO 
        WHERE CAST(data_inicio AS DATE) = CAST(GETDATE() AS DATE)
          AND estado != 'cancelado';
    END
    ELSE
    BEGIN
        SELECT @ConsultasHoje = COUNT(*) 
        FROM SGA_ATENDIMENTO a
        JOIN SGA_TRABALHADOR_ATENDIMENTO ta ON a.num_atendimento = ta.num_atendimento
        WHERE ta.id_trabalhador = @id_trabalhador
          AND CAST(a.data_inicio AS DATE) = CAST(GETDATE() AS DATE)
          AND a.estado != 'cancelado';
    END

    SELECT 
        @TotalPacientes AS TotalPacientes, 
        @TotalEquipa AS TotalEquipa, 
        @ConsultasHoje AS ConsultasHoje;
END
GO

CREATE OR ALTER PROCEDURE sp_ObterProximasConsultas
    @id_trabalhador INT,
    @perfil VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 5
        a.num_atendimento,
        p.nome AS Paciente,
        a.data_inicio,
        a.estado,
        t_pess.nome AS Medico
    FROM SGA_ATENDIMENTO a
    JOIN SGA_PACIENTE_ATENDIMENTO pa ON a.num_atendimento = pa.num_atendimento
    JOIN SGA_PACIENTE pac ON pa.id_paciente = pac.id_paciente
    JOIN SGA_PESSOA p ON pac.NIF = p.NIF
    JOIN SGA_TRABALHADOR_ATENDIMENTO ta ON a.num_atendimento = ta.num_atendimento
    JOIN SGA_TRABALHADOR t ON ta.id_trabalhador = t.id_trabalhador
    JOIN SGA_PESSOA t_pess ON t.NIF = t_pess.NIF
    WHERE 
        a.data_inicio >= CAST(GETDATE() AS DATE)
        AND a.estado != 'cancelado'
        AND (@perfil = 'admin' OR ta.id_trabalhador = @id_trabalhador)
    ORDER BY a.data_inicio ASC;
END
GO

CREATE OR ALTER PROCEDURE sp_contarSalasLivresAgora
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @TotalSalasFisicas INT;
    DECLARE @SalasOcupadasAgora INT;

    SELECT @TotalSalasFisicas = COUNT(*) FROM SGA_SALA WHERE is_online = 0 AND ativa = 1;

    SELECT @SalasOcupadasAgora = COUNT(DISTINCT a.id_sala)
    FROM SGA_ATENDIMENTO a
    JOIN SGA_SALA s ON a.id_sala = s.id_sala
    WHERE s.is_online = 0 
      AND a.estado = 'a decorrer' 
      AND a.estado != 'cancelado';

    SELECT CASE 
        WHEN (@TotalSalasFisicas - @SalasOcupadasAgora) < 0 THEN 0 
        ELSE (@TotalSalasFisicas - @SalasOcupadasAgora) 
    END AS salas_livres;
END
GO

CREATE OR ALTER PROC sp_countConsultasHoje
AS
BEGIN
    SET NOCOUNT ON;
    SELECT 
        COUNT(*) AS total,
        SUM(CASE WHEN s.is_online = 1 THEN 1 ELSE 0 END) AS online,
        SUM(CASE WHEN s.is_online = 0 THEN 1 ELSE 0 END) AS presencial
    FROM SGA_ATENDIMENTO a
    JOIN SGA_SALA s ON a.id_sala = s.id_sala
    WHERE CAST(a.data_inicio AS DATE) = CAST(GETDATE() AS DATE)
      AND a.estado != 'cancelado';
END
GO

-- =============================================
-- 3. AGENDA (Refatorada com UDFs)
-- =============================================

CREATE OR ALTER PROCEDURE sp_ObterHorariosLivres
    @id_medico INT,
    @data_consulta DATE,
    @is_online BIT = 0,
    @duracao INT = 60,
    @id_atendimento_ignorar INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @HoraInicio TIME = '09:00';
    DECLARE @HoraFim TIME = '18:00';
    
    CREATE TABLE #Slots (Hora TIME);

    DECLARE @HoraAtual TIME = @HoraInicio;
    WHILE @HoraAtual < @HoraFim
    BEGIN
        IF @HoraAtual != '13:00' INSERT INTO #Slots VALUES (@HoraAtual);
        SET @HoraAtual = DATEADD(MINUTE, 60, @HoraAtual);
    END

    -- REFACTOR: Uso da UDF udf_VerificarColisaoMedico para limpar o código
    SELECT LEFT(CAST(s.Hora AS VARCHAR), 5) AS Hora
    FROM #Slots s
    WHERE 
        (
            (s.Hora >= '09:00' AND DATEADD(MINUTE, @duracao, s.Hora) <= '13:00')
            OR
            (s.Hora >= '14:00' AND DATEADD(MINUTE, @duracao, s.Hora) <= '18:00')
        )
        AND
        -- Chama a nova função (retorna 0 se livre, 1 se ocupado)
        dbo.udf_VerificarColisaoMedico(
            @id_medico, 
            CAST(CAST(@data_consulta AS VARCHAR) + ' ' + CAST(s.Hora AS VARCHAR) AS DATETIME2),
            @duracao,
            @id_atendimento_ignorar
        ) = 0;

    DROP TABLE #Slots;
END
GO

CREATE OR ALTER PROC sp_listarMedicosAgenda
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        SELECT t.id_trabalhador, p.nome
        FROM SGA_TRABALHADOR as t JOIN SGA_PESSOA as p ON t.nif = p.nif
        WHERE ativo = 1
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_ListarPacientesParaAgenda
    @id_trabalhador INT,
    @perfil VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    IF @perfil = 'admin'
    BEGIN
        SELECT Pac.id_paciente, P.nome, P.NIF 
        FROM SGA_PACIENTE Pac
        JOIN SGA_PESSOA P ON Pac.NIF = P.NIF
        WHERE Pac.ativo = 1
        ORDER BY P.nome
    END
    ELSE
    BEGIN
        SELECT Pac.id_paciente, P.nome, P.NIF
        FROM SGA_PACIENTE Pac
        JOIN SGA_PESSOA P ON Pac.NIF = P.NIF
        JOIN SGA_VINCULO_CLINICO V ON Pac.NIF = V.NIF_paciente
        JOIN SGA_TRABALHADOR T ON V.NIF_trabalhador = T.NIF
        WHERE T.id_trabalhador = @id_trabalhador AND Pac.ativo = 1
        ORDER BY P.nome
    END
END
GO

CREATE OR ALTER PROCEDURE sp_criarAgendamento
    @nif_paciente CHAR(9),
    @id_medico INT,
    @data_inicio DATETIME2,
    @preferencia_online BIT,
    @duracao INT = 60
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @id_paciente INT;
    SELECT @id_paciente = id_paciente FROM SGA_PACIENTE WHERE NIF = @nif_paciente AND ativo = 1;
    IF @id_paciente IS NULL THROW 50009, 'Paciente não encontrado.', 1;

    -- REFACTOR: Uso da UDF em vez da query direta
    IF dbo.udf_VerificarColisaoMedico(@id_medico, @data_inicio, @duracao, NULL) = 1
        THROW 50010, 'O médico já tem consulta marcada a essa hora.', 1;

    -- Lógica de Salas
    DECLARE @id_sala_final INT;

    IF @preferencia_online = 1
    BEGIN
        SELECT TOP 1 @id_sala_final = id_sala FROM SGA_SALA WHERE is_online = 1;
    END
    ELSE
    BEGIN
        SELECT @id_sala_final = id_sala FROM SGA_SALA WHERE id_dono = @id_medico AND ativa = 1;

        IF @id_sala_final IS NULL
        BEGIN
            SELECT TOP 1 @id_sala_final = s.id_sala
            FROM SGA_SALA s
            WHERE s.is_online = 0 AND s.ativa = 1 AND s.id_dono IS NULL
            AND s.id_sala NOT IN (
                SELECT a.id_sala FROM SGA_ATENDIMENTO a
                WHERE a.estado != 'cancelado' 
                AND (@data_inicio >= a.data_inicio AND @data_inicio < a.data_fim)
            )
        END
    END

    IF @id_sala_final IS NULL 
        THROW 50011, 'Não foi possível alocar sala (Médico sem gabinete e salas comuns cheias).', 1;

    -- Transação
    BEGIN TRY
        BEGIN TRAN
            DECLARE @nif_medico_agenda CHAR(9);
            SELECT @nif_medico_agenda = NIF FROM SGA_TRABALHADOR WHERE id_trabalhador = @id_medico;

            IF @nif_medico_agenda IS NOT NULL AND NOT EXISTS (
                SELECT 1 FROM SGA_VINCULO_CLINICO WHERE NIF_trabalhador = @nif_medico_agenda AND NIF_paciente = @nif_paciente
            )
            INSERT INTO SGA_VINCULO_CLINICO (NIF_trabalhador, NIF_paciente, tipo_vinculo) VALUES (@nif_medico_agenda, @nif_paciente, 'Responsável');

            INSERT INTO SGA_ATENDIMENTO (id_sala, data_inicio, data_fim, estado)
            VALUES (@id_sala_final, @data_inicio, DATEADD(MINUTE, @duracao, @data_inicio), 'agendado');
            
            DECLARE @new_id INT = SCOPE_IDENTITY();
            INSERT INTO SGA_TRABALHADOR_ATENDIMENTO (id_trabalhador, num_atendimento) VALUES (@id_medico, @new_id);
            INSERT INTO SGA_PACIENTE_ATENDIMENTO (id_paciente, num_atendimento, presenca) VALUES (@id_paciente, @new_id, 0);
        COMMIT TRAN
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_obterDetalhesAtendimento
    @id_atendimento INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT 
        A.num_atendimento,
        PessPac.nome AS NomePaciente,
        PessPac.NIF AS NifPaciente,
        PessMed.nome AS NomeMedico,
        T.id_trabalhador AS IdMedico,
        A.data_inicio,
        A.data_fim,
        A.estado
    FROM SGA_ATENDIMENTO A
    JOIN SGA_PACIENTE_ATENDIMENTO PA ON A.num_atendimento = PA.num_atendimento
    JOIN SGA_PACIENTE Pac ON PA.id_paciente = Pac.id_paciente
    JOIN SGA_PESSOA PessPac ON Pac.NIF = PessPac.NIF
    JOIN SGA_TRABALHADOR_ATENDIMENTO TA ON A.num_atendimento = TA.num_atendimento
    JOIN SGA_TRABALHADOR T ON TA.id_trabalhador = T.id_trabalhador
    JOIN SGA_PESSOA PessMed ON T.NIF = PessMed.NIF
    WHERE A.num_atendimento = @id_atendimento;
END
GO

CREATE OR ALTER PROCEDURE sp_listarEventosCalendario
    @id_user INT,
    @perfil VARCHAR(20),
    @filtro_medico INT = NULL,
    @filtro_paciente_nif CHAR(9) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT DISTINCT
        A.num_atendimento,
        PessPac.nome AS NomePaciente,
        A.data_inicio,
        A.data_fim,
        A.estado,
        PessMed.nome AS NomeMedico
    FROM SGA_ATENDIMENTO A
    JOIN SGA_PACIENTE_ATENDIMENTO PA ON A.num_atendimento = PA.num_atendimento
    JOIN SGA_PACIENTE Pac ON PA.id_paciente = Pac.id_paciente
    JOIN SGA_PESSOA PessPac ON Pac.NIF = PessPac.NIF
    JOIN SGA_TRABALHADOR_ATENDIMENTO TA ON A.num_atendimento = TA.num_atendimento
    JOIN SGA_TRABALHADOR T ON TA.id_trabalhador = T.id_trabalhador
    JOIN SGA_PESSOA PessMed ON T.NIF = PessMed.NIF
    WHERE A.estado != 'cancelado'
      AND (
          -- Se for colaborador, SÓ vê os seus (ignora filtro_medico)
          (@perfil = 'colaborador' AND TA.id_trabalhador = @id_user)
          OR
          -- Se for admin, vê tudo OU filtra por médico específico
          (@perfil = 'admin' AND (@filtro_medico IS NULL OR TA.id_trabalhador = @filtro_medico))
      )
      -- Filtro de Paciente (Aplica-se a todos)
      AND (@filtro_paciente_nif IS NULL OR PessPac.NIF = @filtro_paciente_nif);
END
GO

CREATE OR ALTER PROCEDURE sp_editarAgendamento
    @id_atendimento INT,
    @nova_data DATETIME2,
    @nova_duracao INT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @novo_fim DATETIME2 = DATEADD(MINUTE, @nova_duracao, @nova_data);
    DECLARE @id_medico INT;
    SELECT @id_medico = id_trabalhador FROM SGA_TRABALHADOR_ATENDIMENTO WHERE num_atendimento = @id_atendimento;

    -- REFACTOR: Uso da UDF com o parametro de ignorar ID
    IF dbo.udf_VerificarColisaoMedico(@id_medico, @nova_data, @nova_duracao, @id_atendimento) = 1
        THROW 50012, 'O médico já tem consulta marcada nesse horário.', 1;

    UPDATE SGA_ATENDIMENTO 
    SET data_inicio = @nova_data, 
        data_fim = @novo_fim 
    WHERE num_atendimento = @id_atendimento;
END
GO

CREATE OR ALTER PROCEDURE sp_cancelarAgendamento
    @id_atendimento INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE SGA_ATENDIMENTO SET estado = 'cancelado' WHERE num_atendimento = @id_atendimento;
END
GO

-- =============================================
-- 4. GESTÃO DE EQUIPA E PACIENTES
-- =============================================

CREATE OR ALTER PROCEDURE sp_listarEquipa   
AS
BEGIN
    SET NOCOUNT ON;
    SELECT 
        P.nome,                  -- [0]
        P.email,                 -- [1]
        P.telefone,              -- [2]
        T.tipo_perfil,           -- [3]
        ISNULL(T.cedula_profissional, '---'), -- [4]
        P.NIF,                   -- [5] 
        T.id_trabalhador         -- [6] 
    FROM SGA_TRABALHADOR T
    JOIN SGA_PESSOA P ON T.NIF = P.NIF
    WHERE T.ativo = 1;
END;
GO

CREATE OR ALTER PROCEDURE sp_listarEquipaInativa   
AS
BEGIN
    SET NOCOUNT ON;
    SELECT 
        P.nome,                                     -- [0]
        P.email,                                    -- [1]
        P.telefone,                                 -- [2]
        T.tipo_perfil,                              -- [3]
        ISNULL(FORMAT(T.data_fim, 'dd/MM/yyyy'), 'N/A'), -- [4] 
        T.id_trabalhador                            -- [5]
    FROM SGA_TRABALHADOR T
    JOIN SGA_PESSOA P ON T.NIF = P.NIF
    WHERE T.ativo = 0
    ORDER BY P.nome;
END;
GO

CREATE OR ALTER PROCEDURE sp_obterDetalhesTrabalhador
    @id_trabalhador_alvo INT,
    @perfil_quem_pede VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    IF @perfil_quem_pede <> 'admin'
    BEGIN
        THROW 50006, 'Acesso Negado: Apenas administradores podem consultar detalhes da equipa.', 1;
    END

    SELECT 
        P.nome,                  -- [0]
        P.email,                 -- [1]
        P.telefone,              -- [2]
        T.tipo_perfil,           -- [3]
        T.cedula_profissional,   -- [4]
        P.NIF,                   -- [5]
        FORMAT(P.data_nascimento, 'dd/MM/yyyy'), -- [6]
        T.id_trabalhador,        -- [7]
        T.ativo,                 -- [8]
        FORMAT(T.data_inicio, 'dd/MM/yyyy'),     -- [9]
        C.contrato_trabalho,     -- [10]
        S.ordem,                 -- [11]
        S.remuneracao            -- [12]
    FROM SGA_TRABALHADOR T
    JOIN SGA_PESSOA P ON T.NIF = P.NIF
    LEFT JOIN SGA_CONTRATADO C ON T.id_trabalhador = C.id_trabalhador
    LEFT JOIN SGA_PRESTADOR_SERVICO S ON T.id_trabalhador = S.id_trabalhador
    WHERE T.id_trabalhador = @id_trabalhador_alvo;
END;
GO

CREATE OR ALTER PROCEDURE sp_criarFuncionario
    @NIF CHAR(9),
    @nome VARCHAR(50),
    @data_nasc DATE,
    @telemovel CHAR(9),
    @email VARCHAR(100),
    @senha_hash VARCHAR(255),
    @tipo_perfil VARCHAR(20),
    @cedula CHAR(5),
    @categoria VARCHAR(20), 
    @contrato_tipo VARCHAR(20) = NULL,
    @ordem VARCHAR(50) = NULL,
    @remuneracao NUMERIC(10,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    IF EXISTS (SELECT 1 FROM SGA_PESSOA WHERE NIF = @NIF)
    BEGIN
        RAISERROR('O NIF %s já se encontra registado no sistema.', 16, 1, @NIF);
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;
            EXEC sp_guardarPessoa @NIF, @nome, @data_nasc, @telemovel, @email;

            INSERT INTO SGA_TRABALHADOR (NIF, senha_hash, tipo_perfil, cedula_profissional, ativo, data_inicio)
            VALUES (@NIF, @senha_hash, @tipo_perfil, @cedula, 1, GETDATE());

            DECLARE @new_id INT = SCOPE_IDENTITY();

            IF @categoria = 'CONTRATADO'
                INSERT INTO SGA_CONTRATADO (id_trabalhador, contrato_trabalho) VALUES (@new_id, @contrato_tipo);
            ELSE IF @categoria = 'PRESTADOR'
                INSERT INTO SGA_PRESTADOR_SERVICO (id_trabalhador, ordem, remuneracao) VALUES (@new_id, @ordem, @remuneracao);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE sp_editarTrabalhador
    @NIF CHAR(9),
    @nome VARCHAR(50),
    @telefone CHAR(9),
    @email VARCHAR(100),
    @perfil VARCHAR(20),
    @cedula CHAR(5) = NULL,
    @categoria VARCHAR(20), -- 'CONTRATADO' ou 'PRESTADOR'
    @campo_extra VARCHAR(50) = NULL -- Contrato ou Ordem
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
            UPDATE SGA_PESSOA SET nome = @nome, telefone = @telefone, email = @email 
            WHERE NIF = @NIF;

            UPDATE SGA_TRABALHADOR SET tipo_perfil = @perfil, cedula_profissional = @cedula 
            WHERE NIF = @NIF;

            DECLARE @id_trab INT = (SELECT id_trabalhador FROM SGA_TRABALHADOR WHERE NIF = @NIF);

            IF @categoria = 'CONTRATADO'
                UPDATE SGA_CONTRATADO SET contrato_trabalho = @campo_extra WHERE id_trabalhador = @id_trab;
            ELSE
                UPDATE SGA_PRESTADOR_SERVICO SET ordem = @campo_extra WHERE id_trabalhador = @id_trab;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE sp_desativarFuncionario
    @id_trabalhador INT
AS
BEGIN
    SET NOCOUNT ON;
    -- REFACTOR: Simplificado. O Trigger trg_DesativarTrabalhador trata da data_fim automaticamente.
    UPDATE SGA_TRABALHADOR 
    SET ativo = 0 
    WHERE id_trabalhador = @id_trabalhador;
END;
GO

CREATE OR ALTER PROCEDURE sp_ativarFuncionario
    @id_trabalhador INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE SGA_TRABALHADOR 
    SET ativo = 1, 
        data_fim = NULL 
    WHERE id_trabalhador = @id_trabalhador;
END;
GO

CREATE OR ALTER PROCEDURE sp_eliminarTrabalhadorPermanente
    @id_trabalhador INT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM SGA_TRABALHADOR WHERE id_trabalhador = @id_trabalhador AND ativo = 1)
    BEGIN
        RAISERROR('Erro: Não é possível eliminar um funcionário ativo.', 16, 1);
        RETURN;
    END

    DECLARE @nif_t CHAR(9) = (SELECT NIF FROM SGA_TRABALHADOR WHERE id_trabalhador = @id_trabalhador);

    BEGIN TRY
        BEGIN TRANSACTION;
            DELETE FROM SGA_RELATORIO WHERE id_autor = @id_trabalhador;
            UPDATE SGA_SALA SET id_dono = NULL WHERE id_dono = @id_trabalhador;
            DELETE FROM SGA_VINCULO_CLINICO WHERE NIF_trabalhador = @nif_t;
            
            -- FIX 22/12: Apagar associações a atendimentos (o que causava o erro FK)
            DELETE FROM SGA_TRABALHADOR_ATENDIMENTO WHERE id_trabalhador = @id_trabalhador;

            DELETE FROM SGA_CONTRATADO WHERE id_trabalhador = @id_trabalhador;
            DELETE FROM SGA_PRESTADOR_SERVICO WHERE id_trabalhador = @id_trabalhador;
            DELETE FROM SGA_TRABALHADOR WHERE id_trabalhador = @id_trabalhador;
            
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE sp_listarPacientesSGA
    @id_trabalhador INT, 
    @perfil VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    IF @perfil = 'admin'
    BEGIN
        SELECT Pac.id_paciente, P.nome, P.NIF, P.telefone, P.email, 
               FORMAT(Pac.data_inscricao, 'dd/MM/yyyy'), Pac.observacoes
        FROM SGA_PACIENTE Pac
        JOIN SGA_PESSOA P ON Pac.NIF = P.NIF
        WHERE Pac.ativo = 1
        ORDER BY P.nome;
    END
    ELSE
    BEGIN
        DECLARE @nif_medico CHAR(9);
        SELECT @nif_medico = NIF FROM SGA_TRABALHADOR WHERE id_trabalhador = @id_trabalhador;

        SELECT Pac.id_paciente, P.nome, P.NIF, P.telefone, P.email, 
               FORMAT(Pac.data_inscricao, 'dd/MM/yyyy'), Pac.observacoes
        FROM SGA_PACIENTE Pac
        JOIN SGA_PESSOA P ON Pac.NIF = P.NIF
        INNER JOIN SGA_VINCULO_CLINICO V ON Pac.NIF = V.NIF_paciente
        WHERE V.NIF_trabalhador = @nif_medico AND Pac.ativo = 1
        ORDER BY P.nome;
    END
END;
GO

CREATE OR ALTER PROCEDURE sp_desativarPaciente
    @id_paciente INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE SGA_PACIENTE SET ativo = 0 WHERE id_paciente = @id_paciente;
END;
GO

CREATE OR ALTER PROCEDURE sp_listarPacientesInativos
AS
BEGIN
    SET NOCOUNT ON;
    SELECT 
        Pac.id_paciente,    -- [0]
        Pess.nome,          -- [1]
        Pess.NIF,           -- [2]
        Pess.telefone,      -- [3]
        Pac.data_inscricao  -- [4]
    FROM SGA_PACIENTE Pac
    JOIN SGA_PESSOA Pess ON Pac.NIF = Pess.NIF
    WHERE Pac.ativo = 0     
    ORDER BY Pess.nome;
END;
GO

CREATE OR ALTER PROCEDURE sp_ativarPaciente
    @id_paciente INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE SGA_PACIENTE 
    SET ativo = 1 
    WHERE id_paciente = @id_paciente;
END;
GO

CREATE OR ALTER PROCEDURE sp_obterFichaCompletaPaciente
    @id_paciente INT,
    @id_trabalhador INT, 
    @perfil VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @nif_trabalhador CHAR(9);
    SELECT @nif_trabalhador = NIF FROM SGA_TRABALHADOR WHERE id_trabalhador = @id_trabalhador;

    DECLARE @nif_p CHAR(9) = (SELECT NIF FROM SGA_PACIENTE WHERE id_paciente = @id_paciente);

    IF @perfil <> 'admin' AND NOT EXISTS (
        SELECT 1 FROM SGA_VINCULO_CLINICO 
        WHERE NIF_paciente = @nif_p AND NIF_trabalhador = @nif_trabalhador
    )
    BEGIN
        THROW 50005, 'Acesso Negado: Sem permissão clínica para este paciente.', 1;
    END

    SELECT Pac.id_paciente, Pess.nome, Pess.NIF, Pess.data_nascimento, Pess.telefone, Pess.email, Pac.data_inscricao, Pac.observacoes, Pac.ativo
    FROM SGA_PACIENTE Pac
    JOIN SGA_PESSOA Pess ON Pac.NIF = Pess.NIF
    WHERE Pac.id_paciente = @id_paciente;
END;
GO

CREATE OR ALTER PROCEDURE sp_editarPaciente
    @NIF CHAR(9),
    @nome VARCHAR(50),
    @telefone CHAR(9),
    @email VARCHAR(100),
    @obs VARCHAR(250)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;
        UPDATE SGA_PESSOA SET nome = @nome, telefone = @telefone, email = @email 
        WHERE NIF = @NIF; 

        UPDATE SGA_PACIENTE SET observacoes = @obs 
        WHERE NIF = @NIF; 
    COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE sp_atualizarObservacoesPaciente
    @id INT,
    @obs VARCHAR(250)
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM SGA_PACIENTE WHERE id_paciente = @id)
        THROW 50004, 'No existe paciente com esse Id.', 1;

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

CREATE OR ALTER PROCEDURE sp_eliminarPacientePermanente
    @id_paciente INT
AS
BEGIN
    SET NOCOUNT ON;
    
    IF EXISTS (SELECT 1 FROM SGA_PACIENTE WHERE id_paciente = @id_paciente AND ativo = 1)
    BEGIN
        RAISERROR('Erro: Não é possível eliminar um paciente ativo. Desative-o primeiro.', 16, 1);
        RETURN;
    END

    DECLARE @nif_p CHAR(9) = (SELECT NIF FROM SGA_PACIENTE WHERE id_paciente = @id_paciente);

    BEGIN TRY
        BEGIN TRANSACTION;
            DELETE FROM SGA_RELATORIO WHERE id_paciente = @id_paciente;
            DELETE FROM SGA_VINCULO_CLINICO WHERE NIF_paciente = @nif_p;
            
            -- FIX 22/12: Garantir que não falha se tiver histórico
            DELETE FROM SGA_PACIENTE_ATENDIMENTO WHERE id_paciente = @id_paciente;

            DELETE FROM SGA_PACIENTE WHERE id_paciente = @id_paciente;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO

CREATE OR ALTER PROC  sp_countPaciente
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- REFACTOR: Uso de UDF
        SELECT dbo.udf_ContarPacientesAtivos();
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE sp_listarPacientesDeTrabalhador
    @id_trabalhador INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @nif_trab CHAR(9) = (SELECT NIF FROM SGA_TRABALHADOR WHERE id_trabalhador = @id_trabalhador);

    SELECT 
        P.id_paciente, 
        Pe.nome, 
        V.tipo_vinculo,
        FORMAT(V.data_inicio, 'dd/MM/yyyy') as desde
    FROM SGA_VINCULO_CLINICO V
    JOIN SGA_PACIENTE P ON V.NIF_paciente = P.NIF
    JOIN SGA_PESSOA Pe ON P.NIF = Pe.NIF
    WHERE V.NIF_trabalhador = @nif_trab AND P.ativo = 1;
END;
GO

CREATE OR ALTER PROCEDURE sp_listarTrabalhadoresDePaciente
    @id_paciente INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @nif_pac CHAR(9) = (SELECT NIF FROM SGA_PACIENTE WHERE id_paciente = @id_paciente);

    SELECT 
        T.id_trabalhador, 
        Pe.nome, 
        T.tipo_perfil,
        V.tipo_vinculo
    FROM SGA_VINCULO_CLINICO V
    JOIN SGA_TRABALHADOR T ON V.NIF_trabalhador = T.NIF
    JOIN SGA_PESSOA Pe ON T.NIF = Pe.NIF
    WHERE V.NIF_paciente = @nif_pac AND T.ativo = 1;
END;
GO

CREATE OR ALTER PROCEDURE sp_listarProcessosClinicosAtivos
    @id_trabalhador_sessao INT,
    @perfil VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        Pac.id_paciente, 
        P_Pess.nome AS nome_paciente,
        MAX(R.data_criacao) AS ultima_atividade,
        COUNT(R.id) AS total_paragrafos
    FROM SGA_VINCULO_CLINICO V
    JOIN SGA_PACIENTE Pac ON V.NIF_paciente = Pac.NIF
    JOIN SGA_PESSOA P_Pess ON Pac.NIF = P_Pess.NIF
    LEFT JOIN SGA_RELATORIO R ON Pac.id_paciente = R.id_paciente AND R.id_autor = @id_trabalhador_sessao
    JOIN SGA_TRABALHADOR T ON T.id_trabalhador = @id_trabalhador_sessao 
    
    WHERE V.NIF_trabalhador = T.NIF 
      AND (Pac.ativo = 1 OR @perfil = 'admin') 
      
    GROUP BY Pac.id_paciente, P_Pess.nome
    ORDER BY ultima_atividade DESC;
END;
GO

CREATE OR ALTER PROCEDURE sp_salvarRelatorioClinico
    @id_relatorio INT = NULL,
    @id_paciente INT,
    @id_autor INT,
    @conteudo VARCHAR(MAX),
    @tipo VARCHAR(50)
AS
BEGIN
    IF EXISTS (SELECT 1 FROM SGA_RELATORIO WHERE id = @id_relatorio AND id_autor = @id_autor)
    BEGIN
        UPDATE SGA_RELATORIO SET conteudo = @conteudo, tipo_relatorio = @tipo WHERE id = @id_relatorio;
    END
    ELSE
    BEGIN
        INSERT INTO SGA_RELATORIO (id_paciente, id_autor, conteudo, tipo_relatorio)
        VALUES (@id_paciente, @id_autor, @conteudo, @tipo);
    END
END;
GO

CREATE OR ALTER PROCEDURE sp_obterLivrariaRelatorios
    @id_paciente INT,
    @id_autor INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT 
        id, 
        tipo_relatorio, 
        FORMAT(data_criacao, 'dd/MM/yyyy HH:mm') as data_formatada, 
        conteudo 
    FROM SGA_RELATORIO
    WHERE id_paciente = @id_paciente AND id_autor = @id_autor
    ORDER BY data_criacao DESC; 
END;
GO

CREATE OR ALTER PROCEDURE sp_RegistoRapidoAgenda
    @nif CHAR(9),
    @nome VARCHAR(50),
    @telemovel CHAR(9),
    @data_nasc DATE,
    @id_paciente_gerado INT OUTPUT 
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;
            
            MERGE SGA_PESSOA AS target
            USING (SELECT @nif, @nome, @data_nasc, @telemovel) 
               AS source (NIF, nome, data_nascimento, telefone)
            ON (target.NIF = source.NIF)
            WHEN MATCHED THEN
                UPDATE SET nome = source.nome, 
                           data_nascimento = source.data_nascimento, 
                           telefone = source.telefone
            WHEN NOT MATCHED THEN
                INSERT (NIF, nome, data_nascimento, telefone)
                VALUES (source.NIF, source.nome, source.data_nascimento, source.telefone);

            DECLARE @id_existente INT;
            SELECT @id_existente = id_paciente FROM SGA_PACIENTE WHERE NIF = @nif;

            IF @id_existente IS NULL
            BEGIN
                INSERT INTO SGA_PACIENTE (NIF, data_inscricao, observacoes, ativo)
                VALUES (@nif, GETDATE(), 'Registo Rápido via Agenda', 1);
                
                SET @id_paciente_gerado = SCOPE_IDENTITY();
            END
            ELSE
            BEGIN
                UPDATE SGA_PACIENTE SET ativo = 1 WHERE id_paciente = @id_existente;
                SET @id_paciente_gerado = @id_existente;
            END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO