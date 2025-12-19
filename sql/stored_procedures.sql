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

CREATE PROC sp_countPaciente
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

CREATE PROC sp_countPedidosPendentes
AS
/*
-- ==========================================================
-- Autor:       Bernardo Santos
-- Create Date: 18/12/2025
-- Descrição:   Conta pedidos no stado 'pendente'
-- ==========================================================
*/
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        SELECT COUNT(*) FROM SGA_PEDIDO as p WHERE p.estado = 'pendente';
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
    BEGIN TRY
        SELECT 
            COUNT(*) AS total,
            SUM(CASE WHEN sala = 'Online' THEN 1 ELSE 0 END) AS online
        FROM SGA_ATENDIMENTO as a
        WHERE CAST(GETDATE() AS DATE) = CAST(a.data_inicio AS DATE)
            AND a.estado != 'cancelado';
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

CREATE PROCEDURE sp_ObterHorariosLivres
    @id_medico INT,
    @data_consulta DATE
AS
/*
-- ==========================================================
-- Autor:       Bernardo Santos
-- Create Date: 18/12/2025
-- Descrição:   Obter horários livres
-- ==========================================================
*/
BEGIN
    SET NOCOUNT ON;
    
    -- Configuração (Podes ajustar isto)
    DECLARE @HoraInicio TIME = '09:00';
    DECLARE @HoraFim TIME = '18:00';
    DECLARE @DuracaoMinutos INT = 60; 

    -- Tabela temporária para slots
    CREATE TABLE #Slots (Hora TIME);

    -- 1. Gerar todos os slots possíveis
    DECLARE @HoraAtual TIME = @HoraInicio;
    WHILE @HoraAtual < @HoraFim
    BEGIN
        -- Excluir hora de almoço (ex: 13:00) se quiseres
        IF @HoraAtual != '13:00' 
            INSERT INTO #Slots VALUES (@HoraAtual);
            
        SET @HoraAtual = DATEADD(MINUTE, @DuracaoMinutos, @HoraAtual);
    END

    -- 2. Devolver apenas os LIVRES
    SELECT LEFT(CAST(s.Hora AS VARCHAR), 5) AS Hora -- Formata como "09:00"
    FROM #Slots s
    WHERE NOT EXISTS (
        SELECT 1 
        FROM SGA_ATENDIMENTO a
        JOIN SGA_TRABALHADOR_ATENDIMENTO ta ON a.num_atendimento = ta.num_atendimento
        WHERE ta.id_trabalhador = @id_medico
          AND CAST(a.data_inicio AS DATE) = @data_consulta -- Mesmo dia
          AND CAST(a.data_inicio AS TIME) = s.Hora       -- Mesma hora
          AND a.estado != 'cancelado'
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

CREATE OR ALTER PROCEDURE sp_AdmissaoComPedido
    -- Dados Pessoa
    @nif CHAR(9),
    @nome VARCHAR(50),
    @data_nascimento DATE,
    @telefone CHAR(9),
    @email VARCHAR(100),
    -- Dados Paciente
    @observacoes VARCHAR(250),
    -- Dados Pedido
    @id_solicitante INT, -- Quem está a registar (ex: rececionista ou admin)
    @tipo_pedido VARCHAR(50) -- ex: 'Triagem Inicial'
AS
/*
-- ==========================================================
-- Autor:       Bernardo Santos
-- Create Date: 18/12/2025
-- Descrição:   Cria um paciente, se nao existir, e cria um pedido
-- ==========================================================
*/
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRAN
            -- 1. Garantir que a Pessoa existe (Reutiliza a tua lógica)
            EXEC sp_guardarPessoa @nif, @nome, @data_nascimento, @telefone, @email;

            -- 2. Garantir que o Paciente existe
            DECLARE @id_paciente INT;
            SELECT @id_paciente = id_paciente FROM SGA_PACIENTE WHERE NIF = @nif;

            IF @id_paciente IS NULL
            BEGIN
                INSERT INTO SGA_PACIENTE (NIF, data_inscricao, observacoes, ativo)
                VALUES (@nif, GETDATE(), @observacoes, 1);
                SET @id_paciente = SCOPE_IDENTITY();
            END

            -- 3. CRIAR O PEDIDO (O elo de ligação!)
            -- Nota: id_aceitante fica NULL porque ainda ninguém aceitou
            INSERT INTO SGA_PEDIDO (id_paciente, id_solicitante, id_aceitante, tipo_pedido, estado, data_criacao)
            VALUES (@id_paciente, @id_solicitante, NULL, @tipo_pedido, 'pendente', GETDATE());

        COMMIT TRAN
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
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
    IF @perfil = 'admin'
    BEGIN
        -- Admin vê todos os pacientes ativos
        SELECT id_paciente, nome FROM SGA_PESSOA P 
        JOIN SGA_PACIENTE Pac ON P.NIF = Pac.NIF 
        WHERE Pac.ativo = 1
    END
    ELSE
    BEGIN
        -- Médico só vê os seus (O Elo de Segurança)
        SELECT Pac.id_paciente, P.nome 
        FROM SGA_PACIENTE Pac
        JOIN SGA_PESSOA P ON Pac.NIF = P.NIF
        JOIN SGA_VINCULO_CLINICO V ON Pac.id_paciente = V.id_paciente
        WHERE V.id_trabalhador = @id_trabalhador 
          AND Pac.ativo = 1
    END
END
GO








CREATE OR ALTER PROC sp_criarAgendamento
(
    @nif_paciente CHAR(9),
    @id_medico INT,
    @data_inicio DATETIME2
)
AS
/*
-- ==========================================================
-- Autor:       Bernardo Santos
-- Create Date: 19/12/2025
-- Descrição:   Cria um agendamento
-- ==========================================================
*/
BEGIN
    -- validar paciente
    DECLARE @id_paciente INT;
    SELECT @id_paciente = @id_paciente FROM SGA_PACIENTE
    WHERE NIF = @nif_paciente AND ativo = 1

    IF @id_paciente IS NULL
        THROW 50009, 'Paciente nao encontrado', 1;

    -- validar medico
    IF EXISTS (SELECT 1 FROM SGA_ATENDIMENTO)












CREATE OR ALTER PROCEDURE sp_aceitarPedido
    @id_pedido INT,
    @id_trabalhador INT
AS
/*
-- ==========================================================
-- Autor:       Pedro Gonçalves
-- Create Date: 18/12/2025
-- Descrição:   Aceitar os pedidos de consulta
-- ==========================================================
*/
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
            
            -- 1. Obter o id_paciente diretamente da tabela SGA_PEDIDO
            DECLARE @id_paciente INT;
            SELECT @id_paciente = id_paciente FROM SGA_PEDIDO WHERE id_pedido = @id_pedido;

            -- 2. Atualizar o estado para 'aceite' e definir o aceitante
            UPDATE SGA_PEDIDO 
            SET estado = 'aceite', 
                id_aceitante = @id_trabalhador 
            WHERE id_pedido = @id_pedido AND estado = 'pendente';

            -- 3. Criar o Vínculo Clínico automático na tabela intermédia
            IF @id_paciente IS NOT NULL
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM SGA_VINCULO_CLINICO 
                               WHERE id_trabalhador = @id_trabalhador AND id_paciente = @id_paciente)
                BEGIN
                    INSERT INTO SGA_VINCULO_CLINICO (id_trabalhador, id_paciente, tipo_vinculo)
                    VALUES (@id_trabalhador, @id_paciente, 'Responsável via Inbox');
                END
            END
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
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
        WHERE Pac.ativo = 1 -- Apenas ativos
        ORDER BY Pess.nome;
    END
    ELSE
    BEGIN
        SELECT Pac.id_paciente, Pess.nome, Pess.NIF, Pess.telefone, Pess.email, Pac.data_inscricao, Pac.observacoes
        FROM SGA_PACIENTE Pac
        JOIN SGA_PESSOA Pess ON Pac.NIF = Pess.NIF
        JOIN SGA_VINCULO_CLINICO Vin ON Pac.id_paciente = Vin.id_paciente
        WHERE Vin.id_trabalhador = @id_trabalhador AND Pac.ativo = 1 -- Apenas ativos
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
    -- Validação: Admin vê tudo, o Colaborador vê apenas quem está a seu cargo
    IF @perfil <> 'admin' AND NOT EXISTS (
        SELECT 1 FROM SGA_VINCULO_CLINICO 
        WHERE id_paciente = @id_paciente AND id_trabalhador = @id_trabalhador
    )
    BEGIN
        THROW 50005, 'Acesso Negado: Não tem permissão clínica para este paciente.', 1;
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
