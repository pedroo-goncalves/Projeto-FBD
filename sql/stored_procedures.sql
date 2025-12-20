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

    -- Verifica Pessoa
    IF NOT EXISTS (SELECT 1 FROM SGA_PESSOA WHERE NIF = @NIF)
        THROW 50002, 'Pessoa nao encontrada.', 1;

    -- Verifica se Paciente já existe (para devolver o ID em vez de erro)
    DECLARE @id_existente INT;
    SELECT @id_existente = id_paciente FROM SGA_PACIENTE WHERE NIF = @NIF;

    BEGIN TRY
        BEGIN TRANSACTION;
            
            IF @id_existente IS NULL
            BEGIN
                INSERT INTO SGA_PACIENTE (NIF, data_inscricao, observacoes, ativo)
                VALUES (@NIF, @data_inscricao, @observacoes, 1);
                SET @id_paciente = SCOPE_IDENTITY();
            END
            ELSE
            BEGIN
                UPDATE SGA_PACIENTE SET ativo = 1 WHERE id_paciente = @id_existente;
                SET @id_paciente = @id_existente;
            END

            -- LÓGICA CORRIGIDA: Inserir Vínculo usando NIFs
            IF @id_medico_responsavel IS NOT NULL
            BEGIN
                -- 1. Descobrir NIF do Médico
                DECLARE @NifMedico CHAR(9);
                SELECT @NifMedico = NIF FROM SGA_TRABALHADOR WHERE id_trabalhador = @id_medico_responsavel;

                -- 2. Inserir se não existir
                IF @NifMedico IS NOT NULL AND NOT EXISTS (
                    SELECT 1 FROM SGA_VINCULO_CLINICO 
                    WHERE NIF_trabalhador = @NifMedico AND NIF_paciente = @NIF
                )
                BEGIN
                    -- Nota: Removemos 'id_trabalhador' e 'id_paciente' e usamos os NIFs
                    INSERT INTO SGA_VINCULO_CLINICO (NIF_trabalhador, NIF_paciente, tipo_vinculo, data_inicio)
                    VALUES (@NifMedico, @NIF, 'Responsável', GETDATE());
                END
            END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
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
    -- Join agora é via NIF_paciente
    JOIN SGA_VINCULO_CLINICO V ON Pac.NIF = V.NIF_paciente
    -- Join para filtrar pelo ID do médico, mas ligando pelo NIF
    JOIN SGA_TRABALHADOR T ON V.NIF_trabalhador = T.NIF
    WHERE T.id_trabalhador = @id_medico 
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
    -- Join corrigido para NIFs
    JOIN SGA_VINCULO_CLINICO V ON Pac.NIF = V.NIF_paciente
    JOIN SGA_TRABALHADOR T_Logado ON V.NIF_trabalhador = T_Logado.NIF
    WHERE T_Logado.id_trabalhador = @id_trabalhador 
    ORDER BY R.data_criacao DESC;
END
GO

CREATE OR ALTER PROC  sp_countPaciente
AS
/*
-- ==========================================================
-- Autor:       Bernardo Santos
-- Create Date: 18/12/2025
-- Descrição:   Conta os tuplos na tabela SGA_Paciente
-- ==========================================================
*/
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        SELECT COUNT(*) FROM SGA_PACIENTE;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROC sp_countConsultasHoje
AS
/*
-- ==========================================================
-- Autor:       Bernardo Santos
-- Create Date: 18/12/2025
-- Descrição:   Conta consultas com data hoje
-- ==========================================================
*/
BEGIN
    SET NOCOUNT ON;
    SELECT 
        COUNT(*) AS total,
        -- Conta usando a propriedade da sala, não o nome
        SUM(CASE WHEN s.is_online = 1 THEN 1 ELSE 0 END) AS online,
        SUM(CASE WHEN s.is_online = 0 THEN 1 ELSE 0 END) AS presencial
    FROM SGA_ATENDIMENTO a
    JOIN SGA_SALA s ON a.id_sala = s.id_sala
    WHERE CAST(a.data_inicio AS DATE) = CAST(GETDATE() AS DATE)
      AND a.estado != 'cancelado';
END
GO

CREATE OR ALTER PROCEDURE sp_contarSalasLivresAgora
AS
/*
-- ==========================================================
-- Autor:       Bernardo Santos
-- Create Date: 19/12/2025
-- Descrição:   Conta salas livres, no momento
-- ==========================================================
*/
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @TotalSalasFisicas INT;
    DECLARE @SalasOcupadasAgora INT;

    -- excluir salas online
    SELECT @TotalSalasFisicas = COUNT(*) FROM SGA_SALA WHERE is_online = 0 AND ativa = 1;

    -- 2. Quantos estão ocupados neste momento?
    SELECT @SalasOcupadasAgora = COUNT(DISTINCT a.id_sala)
    FROM SGA_ATENDIMENTO a
    JOIN SGA_SALA s ON a.id_sala = s.id_sala
    WHERE s.is_online = 0 -- Só nos interessa ocupação física
      AND a.estado = 'a decorrer' -- Ou validação por hora:
      -- AND GETDATE() BETWEEN a.data_inicio AND a.data_fim
      AND a.estado != 'cancelado';

    -- Retorna as livres (protegendo contra negativos)
    SELECT CASE 
        WHEN (@TotalSalasFisicas - @SalasOcupadasAgora) < 0 THEN 0 
        ELSE (@TotalSalasFisicas - @SalasOcupadasAgora) 
    END AS salas_livres;
END
GO

CREATE OR ALTER PROCEDURE sp_ObterHorariosLivres
    @id_medico INT,
    @data_consulta DATE,
    @is_online BIT = 0,
    @duracao INT = 60,
    @id_atendimento_ignorar INT = NULL -- Novo parâmetro para Edição
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Gerar Slots (09:00 às 17:00 - última hora possível para slot de 1h)
    DECLARE @HoraInicio TIME = '09:00';
    DECLARE @HoraFim TIME = '18:00';
    
    CREATE TABLE #Slots (Hora TIME);

    DECLARE @HoraAtual TIME = @HoraInicio;
    WHILE @HoraAtual < @HoraFim
    BEGIN
        IF @HoraAtual != '13:00' INSERT INTO #Slots VALUES (@HoraAtual);
        SET @HoraAtual = DATEADD(MINUTE, 60, @HoraAtual);
    END

    -- 2. Filtrar Slots Válidos
    SELECT LEFT(CAST(s.Hora AS VARCHAR), 5) AS Hora
    FROM #Slots s
    WHERE 
        -- A. VALIDAÇÃO DE TURNOS (Resolve o bug das 12h e 17h com 2h de duração)
        -- O agendamento tem de caber TOTALMENTE na manhã OU na tarde.
        (
            (s.Hora >= '09:00' AND DATEADD(MINUTE, @duracao, s.Hora) <= '13:00') -- Cabe na Manhã?
            OR
            (s.Hora >= '14:00' AND DATEADD(MINUTE, @duracao, s.Hora) <= '18:00') -- Cabe na Tarde?
        )
        AND
        -- B. VALIDAÇÃO DE COLISÕES (Com médico)
        NOT EXISTS (
            SELECT 1 FROM SGA_TRABALHADOR_ATENDIMENTO ta
            JOIN SGA_ATENDIMENTO a ON ta.num_atendimento = a.num_atendimento
            WHERE ta.id_trabalhador = @id_medico
              AND a.estado != 'cancelado'
              -- O TRUQUE: Ignorar o atendimento que estamos a tentar editar!
              AND (@id_atendimento_ignorar IS NULL OR a.num_atendimento != @id_atendimento_ignorar)
              AND (
                  CAST(a.data_inicio AS DATE) = @data_consulta
                  AND 
                  (
                      CAST(a.data_inicio AS TIME) < DATEADD(MINUTE, @duracao, s.Hora)
                      AND 
                      CAST(a.data_fim AS TIME) > s.Hora
                  )
              )
        );

    DROP TABLE #Slots;
END
GO

CREATE OR ALTER PROC sp_listarMedicosAgenda
AS
/*
-- ==========================================================
-- Autor:       Bernardo Santos
-- Create Date: 18/12/2025
-- Descrição:   Busca a lista de medicos para o dropdown da agenda
-- ==========================================================
*/
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
/*
-- ==========================================================
-- Autor:       Bernardo Santos
-- Create Date: 19/12/2025
-- Descrição:   Busca a lista de pacientes com vinculo medico
-- ==========================================================
*/
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
        -- Médico vê só os seus (Via NIF)
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
    
    -- 1. Validar Paciente
    DECLARE @id_paciente INT;
    SELECT @id_paciente = id_paciente FROM SGA_PACIENTE WHERE NIF = @nif_paciente AND ativo = 1;
    IF @id_paciente IS NULL THROW 50009, 'Paciente não encontrado.', 1;

    -- 2. Validar se o Médico está livre
    IF EXISTS (
        SELECT 1 FROM SGA_TRABALHADOR_ATENDIMENTO ta
        JOIN SGA_ATENDIMENTO a ON ta.num_atendimento = a.num_atendimento
        WHERE ta.id_trabalhador = @id_medico 
          AND a.estado != 'cancelado'
          AND (@data_inicio >= a.data_inicio AND @data_inicio < a.data_fim)
    )
    THROW 50010, 'O médico já tem consulta marcada a essa hora.', 1;

    -- 3. ALOCAR SALA (Lógica de Gabinete Fixo)
    DECLARE @id_sala_final INT;

    IF @preferencia_online = 1
    BEGIN
        -- Sala Virtual
        SELECT TOP 1 @id_sala_final = id_sala FROM SGA_SALA WHERE is_online = 1;
    END
    ELSE
    BEGIN
        -- A. Tenta encontrar o Gabinete DO Médico
        SELECT @id_sala_final = id_sala FROM SGA_SALA WHERE id_dono = @id_medico AND ativa = 1;

        -- B. Fallback: Se o médico não tiver gabinete fixo, procura uma sala "sem dono" livre
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

    -- 4. Gravar (Com a lógica de Auto-Vínculo NIF que já tinhas)
    BEGIN TRY
        BEGIN TRAN
            -- (O teu código de vínculo NIF aqui...)
            DECLARE @nif_medico_agenda CHAR(9);
            SELECT @nif_medico_agenda = NIF FROM SGA_TRABALHADOR WHERE id_trabalhador = @id_medico;

            IF @nif_medico_agenda IS NOT NULL AND NOT EXISTS (
                SELECT 1 FROM SGA_VINCULO_CLINICO WHERE NIF_trabalhador = @nif_medico_agenda AND NIF_paciente = @nif_paciente
            )
            INSERT INTO SGA_VINCULO_CLINICO (NIF_trabalhador, NIF_paciente, tipo_vinculo) VALUES (@nif_medico_agenda, @nif_paciente, 'Responsável');

            -- Inserir Duracao
            INSERT INTO SGA_ATENDIMENTO (id_sala, data_inicio, data_fim, estado)
            VALUES (@id_sala_final, @data_inicio, DATEADD(MINUTE, @duracao, @data_inicio), 'agendado');

            -- Inserir Atendimento
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

CREATE OR ALTER PROCEDURE sp_listarEquipa   
AS
/*
-- ==========================================================
-- Autor:       Pedro Gonçalves
-- Create Date: 18/12/2025
-- Descrição:   Procedure para mostrar todos os funcionários ativos do sistema na página equipa.html
-- ==========================================================
*/
BEGIN
    SET NOCOUNT ON;
    SELECT 
        P.nome,                                  -- [0]
        P.email,                                 -- [1]
        P.telefone,                              -- [2]
        T.tipo_perfil,                           -- [3]
        ISNULL(T.cedula_profissional, '-----'),  -- [4]
        T.id_trabalhador                         -- [5] 
    FROM SGA_TRABALHADOR T
    JOIN SGA_PESSOA P ON T.NIF = P.NIF
    WHERE T.ativo = 1;
END;
GO

CREATE OR ALTER PROCEDURE sp_ativarFuncionario
    @id_trabalhador INT
AS
/*
-- ==========================================================
-- Autor:       Pedro Gonçalves
-- Create Date: 18/12/2025
-- Descrição:   Procedure para reativar um funcionário na BD
-- ==========================================================
*/
BEGIN
    SET NOCOUNT ON;
    UPDATE SGA_TRABALHADOR 
    SET ativo = 1, 
        data_fim = NULL 
    WHERE id_trabalhador = @id_trabalhador;
END;
GO


CREATE OR ALTER PROCEDURE sp_listarEquipaInativa   
AS
/*
-- ==========================================================
-- Autor:       Pedro Gonçalves
-- Create Date: 18/12/2025
-- Descrição:   Procedure para mostrar todos os funcionários inativos do sistema na página equipa.html
-- ==========================================================
*/
BEGIN
    SET NOCOUNT ON;
    SELECT 
        P.nome,                                     -- [0]
        P.email,                                    -- [1]
        P.telefone,                                 -- [2]
        T.tipo_perfil,                              -- [3]
        ISNULL(FORMAT(T.data_fim, 'dd/MM/yyyy'), 'N/A'), -- [4] Já vai como texto formatado
        T.id_trabalhador                            -- [5]
    FROM SGA_TRABALHADOR T
    JOIN SGA_PESSOA P ON T.NIF = P.NIF
    WHERE T.ativo = 0
    ORDER BY P.nome;
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
/*
-- ==========================================================
-- Autor:       Pedro Gonçalves
-- Create Date: 18/12/2025
-- Descrição:   Procedure para criar funcionários no sistema, apenas para quem tem a permissão de ADMIN
-- ==========================================================
*/
BEGIN
    SET NOCOUNT ON;
    
    -- VERIFICAÇÃO PREVENTIVA: Impede o erro de NIF duplicado
    IF EXISTS (SELECT 1 FROM SGA_PESSOA WHERE NIF = @NIF)
    BEGIN
        RAISERROR('O NIF %s já se encontra registado no sistema.', 16, 1, @NIF);
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;
            -- 1. Criar Pessoa
            EXEC sp_guardarPessoa @NIF, @nome, @data_nasc, @telemovel, @email;

            -- 2. Criar Trabalhador Base
            INSERT INTO SGA_TRABALHADOR (NIF, senha_hash, tipo_perfil, cedula_profissional, ativo, data_inicio)
            VALUES (@NIF, @senha_hash, @tipo_perfil, @cedula, 1, GETDATE());

            DECLARE @new_id INT = SCOPE_IDENTITY();

            -- 3. Inserir especialidade
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

CREATE OR ALTER PROCEDURE sp_desativarFuncionario
    @id_trabalhador INT
AS
/*
-- ==========================================================
-- Autor:       Pedro Gonçalves
-- Create Date: 18/12/2025
-- Descrição:   Desativar um funcionário na página
-- ==========================================================
*/
BEGIN
    SET NOCOUNT ON;
    -- Em vez de apagar, marcamos como inativo para preservar o histórico
    UPDATE SGA_TRABALHADOR 
    SET ativo = 0, 
        data_fim = GETDATE() 
    WHERE id_trabalhador = @id_trabalhador;
END;
GO



CREATE OR ALTER PROCEDURE sp_listarPacientesSGA
    @id_trabalhador INT,
    @perfil VARCHAR(20)
AS
/*
-- ==========================================================
-- Autor:       Pedro Gonçalves
-- Create Date: 18/12/2025
-- Descrição:   Listar os pacientes no sistema (se Admin é vê tudo, se não for vê apenas os que estão a seu cargo)
-- ==========================================================
*/
BEGIN
    SET NOCOUNT ON;
    IF @perfil = 'admin'
    BEGIN
        SELECT Pac.id_paciente, Pess.nome, Pess.NIF, Pess.telefone, Pess.email, Pac.data_inscricao, Pac.observacoes
        FROM SGA_PACIENTE Pac
        JOIN SGA_PESSOA Pess ON Pac.NIF = Pess.NIF
        WHERE Pac.ativo = 1
        ORDER BY Pess.nome;
    END
    ELSE
    BEGIN
        SELECT Pac.id_paciente, Pess.nome, Pess.NIF, Pess.telefone, Pess.email, Pac.data_inscricao, Pac.observacoes
        FROM SGA_PACIENTE Pac
        JOIN SGA_PESSOA Pess ON Pac.NIF = Pess.NIF
        -- Join Corrigido
        JOIN SGA_VINCULO_CLINICO Vin ON Pac.NIF = Vin.NIF_paciente
        JOIN SGA_TRABALHADOR T ON Vin.NIF_trabalhador = T.NIF
        WHERE T.id_trabalhador = @id_trabalhador AND Pac.ativo = 1
        ORDER BY Pess.nome;
    END
END;
GO

CREATE OR ALTER PROCEDURE sp_desativarPaciente
    @id_paciente INT
AS

/*
-- ==========================================================
-- Autor:       Pedro Gonçalves
-- Create Date: 18/12/2025
-- Descrição:   Desativa os pacientes no sistema (se Admin)
-- ==========================================================
*/
BEGIN
    SET NOCOUNT ON;
    UPDATE SGA_PACIENTE SET ativo = 0 WHERE id_paciente = @id_paciente;
END;
GO

CREATE OR ALTER PROCEDURE sp_listarPacientesInativos
AS
/*
-- ==========================================================
-- Autor:       Pedro Gonçalves
-- Create Date: 18/12/2025
-- Descrição:   Permite listar os pacientes que já foram desativados no sistema (ADMIN)
-- ==========================================================
*/
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
    WHERE Pac.ativo = 0     -- Filtra apenas os inativos
    ORDER BY Pess.nome;
END;
GO

CREATE OR ALTER PROCEDURE sp_ativarPaciente
    @id_paciente INT
AS
/*
-- ==========================================================
-- Autor:       Pedro Gonçalves
-- Create Date: 18/12/2025
-- Descrição:   Permite reativar um paciente inativo
-- ==========================================================
*/
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
/*
-- ==========================================================
-- Autor:       Pedro Gonçalves
-- Create Date: 18/12/2025
-- Descrição:   Permite aceder a todas as informações dos pacientes na página de detalhes 
--              se for admin~. Se for trabalhador, acede apenas aos detalhes dos pacientes a seu cargo
-- ==========================================================
*/
BEGIN
    SET NOCOUNT ON;
    
    -- Se for admin, passa direto. Se for colaborador, verifica vínculo via NIF.
    IF @perfil <> 'admin'
    BEGIN
        -- Obter NIFs para validar
        DECLARE @NifP CHAR(9), @NifT CHAR(9);
        SELECT @NifP = NIF FROM SGA_PACIENTE WHERE id_paciente = @id_paciente;
        SELECT @NifT = NIF FROM SGA_TRABALHADOR WHERE id_trabalhador = @id_trabalhador;

        IF NOT EXISTS (
            SELECT 1 FROM SGA_VINCULO_CLINICO 
            WHERE NIF_paciente = @NifP AND NIF_trabalhador = @NifT
        )
        BEGIN
            THROW 50005, 'Acesso Negado: Não tem permissão clínica para este paciente.', 1;
        END
    END

    SELECT 
        Pac.id_paciente, Pess.nome, Pess.NIF, Pess.data_nascimento, 
        Pess.telefone, Pess.email, Pac.data_inscricao, Pac.observacoes, Pac.ativo
    FROM SGA_PACIENTE Pac
    JOIN SGA_PESSOA Pess ON Pac.NIF = Pess.NIF
    WHERE Pac.id_paciente = @id_paciente;
END;
GO

CREATE OR ALTER PROCEDURE sp_obterDetalhesTrabalhador
    @id_trabalhador_alvo INT,
    @perfil_quem_pede VARCHAR(20)
AS
/*
-- ==========================================================
-- Autor:       Pedro Gonçalves
-- Create Date: 18/12/2025
-- Descrição:   Permite aceder a todas as informações dos trabalhadores na página de detalhes 
--              apenas se for admin, consegue ver tudo de todos, em caso contrário não consegue
-- ==========================================================
*/
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
        -- FORMATAMOS AQUI PARA TEXTO:
        ISNULL(FORMAT(P.data_nascimento, 'dd/MM/yyyy'), '---') AS data_nascimento, -- [6]
        T.id_trabalhador,        -- [7]
        T.ativo,                 -- [8]
        -- FORMATAMOS AQUI TAMBÉM:
        ISNULL(FORMAT(T.data_inicio, 'dd/MM/yyyy'), '---') AS data_inicio,         -- [9]
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

CREATE OR ALTER PROCEDURE sp_RegistoRapidoAgenda
    @nif CHAR(9),
    @nome VARCHAR(50),
    @telemovel CHAR(9),
    @data_nasc DATE,
    @id_paciente_gerado INT OUTPUT -- Parâmetro de saída
AS
/*
-- ==========================================================
-- Autor:       Bernardo Santos
-- Create Date: 19/12/2025
-- Descrição:   Cria paciente novo com registo rapido
                no agendamento
-- ==========================================================
*/
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;
            
            -- 1. TRATAR DA PESSOA (Lógica Upsert)
            -- Não chamamos a outra SP para evitar conflitos de transações aninhadas (COMMITs internos)
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

            -- 2. TRATAR DO PACIENTE
            DECLARE @id_existente INT;
            SELECT @id_existente = id_paciente FROM SGA_PACIENTE WHERE NIF = @nif;

            IF @id_existente IS NULL
            BEGIN
                -- Inserir Novo
                INSERT INTO SGA_PACIENTE (NIF, data_inscricao, observacoes, ativo)
                VALUES (@nif, GETDATE(), 'Registo Rápido via Agenda', 1);
                
                SET @id_paciente_gerado = SCOPE_IDENTITY();
            END
            ELSE
            BEGIN
                -- Reativar Existente
                UPDATE SGA_PACIENTE SET ativo = 1 WHERE id_paciente = @id_existente;
                SET @id_paciente_gerado = @id_existente;
            END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        -- Isto sim, é um ROLLBACK real de base de dados
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        
        -- Relança o erro para o Python saber que falhou
        THROW;
    END CATCH
END
GO








-- 1. Obter Detalhes de um Agendamento
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

-- 2. Editar Agendamento (Data/Hora)
CREATE OR ALTER PROCEDURE sp_editarAgendamento
    @id_atendimento INT,
    @nova_data DATETIME2,
    @nova_duracao INT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @novo_fim DATETIME2 = DATEADD(MINUTE, @nova_duracao, @nova_data);
    
    -- Descobrir quem é o médico deste atendimento
    DECLARE @id_medico INT;
    SELECT @id_medico = id_trabalhador FROM SGA_TRABALHADOR_ATENDIMENTO WHERE num_atendimento = @id_atendimento;

    -- Validar colisão de horário (excluindo o próprio agendamento!)
    IF EXISTS (
        SELECT 1 FROM SGA_TRABALHADOR_ATENDIMENTO ta
        JOIN SGA_ATENDIMENTO a ON ta.num_atendimento = a.num_atendimento
        WHERE ta.id_trabalhador = @id_medico 
          AND a.num_atendimento != @id_atendimento -- Importante: não chocar consigo mesmo
          AND a.estado != 'cancelado'
          AND (@nova_data < a.data_fim AND @novo_fim > a.data_inicio)
    )
    THROW 50012, 'O médico já tem consulta marcada nesse horário.', 1;

    -- Atualizar
    UPDATE SGA_ATENDIMENTO 
    SET data_inicio = @nova_data, 
        data_fim = @novo_fim 
    WHERE num_atendimento = @id_atendimento;
END
GO

-- 3. Cancelar Agendamento
CREATE OR ALTER PROCEDURE sp_cancelarAgendamento
    @id_atendimento INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE SGA_ATENDIMENTO SET estado = 'cancelado' WHERE num_atendimento = @id_atendimento;
END
GO