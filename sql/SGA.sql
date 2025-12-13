CREATE TABLE SGA_PESSOA(
    NIF CHAR(9) PRIMARY KEY,
    nome VARCHAR(50) NOT NULL,
    data_nascimento DATE NOT NULL,
    telefone CHAR(9) NOT NULL
);

CREATE TABLE SGA_TRABALHADOR(
    id_trabalhador INT IDENTITY(1,1) PRIMARY KEY,
    cedula_profissional CHAR(5) UNIQUE NOT NULL,
    NIF CHAR(9) UNIQUE,
    data_inicio DATE,
    data_fim DATE,
    FOREIGN KEY (NIF) REFERENCES SGA_PESSOA(NIF)
);

CREATE TABLE SGA_PACIENTE(
    id_paciente INT IDENTITY(1,1) PRIMARY KEY,
    NIF CHAR(9) UNIQUE NOT NULL,
    data_inscricao DATE NOT NULL,
    observacoes VARCHAR(250),
    FOREIGN KEY (NIF) REFERENCES SGA_PESSOA(NIF)
);

CREATE TABLE SGA_ATENDIMENTO(
    num_atendimento INT IDENTITY(1,1) PRIMARY KEY,
    sala VARCHAR(5) NOT NULL,
    data_inicio DATETIME2 NOT NULL,
    data_fim DATETIME2 NOT NULL,
    estado VARCHAR(20) CHECK (estado IN ('cancelado','a decorrer','agendado','finalizado')),
    CHECK (data_fim > data_inicio)
);

CREATE TABLE SGA_TRABALHADOR_ATENDIMENTO(
    id_trabalhador INT,
    num_atendimento INT,
    PRIMARY KEY (id_trabalhador, num_atendimento),
    FOREIGN KEY (id_trabalhador) REFERENCES SGA_TRABALHADOR(id_trabalhador),
    FOREIGN KEY (num_atendimento) REFERENCES SGA_ATENDIMENTO(num_atendimento)
);

CREATE TABLE SGA_PACIENTE_ATENDIMENTO(
    id_paciente INT,
    num_atendimento INT,
    observacoes VARCHAR(250),
    presenca BIT,
    PRIMARY KEY (id_paciente, num_atendimento),
    FOREIGN KEY (id_paciente) REFERENCES SGA_PACIENTE(id_paciente),
    FOREIGN KEY (num_atendimento) REFERENCES SGA_ATENDIMENTO(num_atendimento)
);

CREATE TABLE SGA_RELATORIO(
    id INT IDENTITY(1,1) PRIMARY KEY,
    id_paciente INT,
    data_criacao DATETIME2,
    conteudo VARCHAR(1000),
    FOREIGN KEY (id_paciente) REFERENCES SGA_PACIENTE(id_paciente)
);

CREATE TABLE SGA_TRABALHADOR_RELATORIO(
    id_trabalhador INT,
    id_relatorio INT,
    PRIMARY KEY (id_trabalhador, id_relatorio),
    FOREIGN KEY (id_trabalhador) REFERENCES SGA_TRABALHADOR(id_trabalhador),
    FOREIGN KEY (id_relatorio) REFERENCES SGA_RELATORIO(id)
);

CREATE TABLE SGA_PEDIDO(
    id_pedido INT IDENTITY(1,1) PRIMARY KEY,
    id_paciente INT,
    estado VARCHAR(20) CHECK (estado IN ('avaliacao pendente','cancelado','aceite','rejeitado')),
    FOREIGN KEY (id_paciente) REFERENCES SGA_PACIENTE(id_paciente)
);

CREATE TABLE SGA_TRABALHADOR_PEDIDO(
    id_trabalhador INT,
    id_pedido INT,
    data_avaliacao DATETIME2 NOT NULL,
    reencaminhado BIT NOT NULL,
    PRIMARY KEY (id_trabalhador, id_pedido),
    FOREIGN KEY (id_trabalhador) REFERENCES SGA_TRABALHADOR(id_trabalhador),
    FOREIGN KEY (id_pedido) REFERENCES SGA_PEDIDO(id_pedido)
);

CREATE TABLE SGA_CONTRATADO(
    id_trabalhador INT PRIMARY KEY,
    contrato_trabalho VARCHAR(10),
    FOREIGN KEY (id_trabalhador) REFERENCES SGA_TRABALHADOR(id_trabalhador)
);

CREATE TABLE SGA_PRESTADOR_SERVICO(
    id_trabalhador INT PRIMARY KEY,
    ordem VARCHAR(50),
    remuneracao NUMERIC(10,2) CHECK (remuneracao > 0),
    FOREIGN KEY (id_trabalhador) REFERENCES SGA_TRABALHADOR(id_trabalhador)
);
