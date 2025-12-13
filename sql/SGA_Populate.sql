-- Pessoas
INSERT INTO SGA_PESSOA (NIF, nome, data_nascimento, telefone) VALUES
  ('123456789', 'Ana Silva', '1985-04-12', '912345678'),
  ('223456780', 'Bruno Costa', '1978-11-05', '913456789'),
  ('323456781', 'Carla Ribeiro', '1990-07-23', '914567890'),
  ('423456782', 'Diogo Ferreira', '1982-02-17', '915678901'),
  ('523456783', 'Eva Sousa', '1995-09-30', '916789012'),
  ('623456784', 'Fábio Martins', '1988-03-15', '917890123'),
  ('723456785', 'Gabriela Lopes', '1992-12-01', '918901234');

-- Trabalhadores
INSERT INTO SGA_TRABALHADOR (cedula_profissional, NIF, data_inicio, data_fim) VALUES
  ('CP001', '123456789', '2022-01-01', NULL),
  ('CP002', '223456780', '2021-06-15', '2024-06-15'),
  ('CP003', '323456781', '2023-03-01', NULL),
  ('CP004', '423456782', '2022-11-20', NULL),
  ('CP005', '523456783', '2020-05-10', '2023-05-10');

-- Tipos de trabalhador
INSERT INTO SGA_CONTRATADO (id_trabalhador, contrato_trabalho) VALUES
  (1, 'FullTime'),
  (2, 'PartTime'),
  (4, 'FullTime');

INSERT INTO SGA_PRESTADOR_SERVICO (id_trabalhador, ordem, remuneracao) VALUES
  (3, 'Ordem A', 50.00),
  (5, 'Ordem B', 75.00);

-- Pacientes (ligados a Pessoa via NIF)
INSERT INTO SGA_PACIENTE (NIF, data_inscricao, observacoes) VALUES
  ('623456784', '2024-01-10', 'Paciente com hipertensão'),
  ('723456785', '2023-11-05', 'Diabético tipo 2'),
  ('123456789', '2024-06-20', 'Acompanhamento psicológico'),
  ('223456780', '2024-07-15', NULL);

-- Atendimentos
INSERT INTO SGA_ATENDIMENTO (sala, data_inicio, data_fim, estado) VALUES
  ('101', '2024-10-01 09:00', '2024-10-01 10:00', 'agendado'),
  ('102', '2024-10-02 14:00', '2024-10-02 15:30', 'a decorrer'),
  ('103', '2024-10-03 08:30', '2024-10-03 09:15', 'finalizado'),
  ('101', '2024-10-04 10:00', '2024-10-04 11:00', 'cancelado');

-- Associar Trabalhadores a Atendimentos
INSERT INTO SGA_TRABALHADOR_ATENDIMENTO (id_trabalhador, num_atendimento) VALUES
  (1, 1),
  (3, 2),
  (4, 3),
  (1, 4);

-- Associar Pacientes a Atendimentos
INSERT INTO SGA_PACIENTE_ATENDIMENTO (id_paciente, num_atendimento, observacoes, presenca) VALUES
  (1, 1, 'Primeira consulta', 1),
  (2, 2, 'Reavaliação', 1),
  (3, 3, 'Sessão regular', 1),
  (4, 4, 'Paciente não apareceu', 0);

-- Pedidos
INSERT INTO SGA_PEDIDO (id_paciente, estado) VALUES
  (1, 'avaliacao pendente'),
  (2, 'aceite'),
  (3, 'rejeitado'),
  (4, 'cancelado');

-- Avaliação de Pedidos
INSERT INTO SGA_TRABALHADOR_PEDIDO (id_trabalhador, id_pedido, data_avaliacao, reencaminhado) VALUES
  (1, 2, '2024-09-20', 0),
  (3, 3, '2024-09-25', 1),
  (4, 4, '2024-09-30', 0);

-- Relatórios
INSERT INTO SGA_RELATORIO (id_paciente, data_criacao, conteudo) VALUES
  (1, '2024-10-01 11:00', 'Relatório inicial: histórico de hipertensão, medicação, plano de tratamento'),
  (2, '2024-10-02 16:00', 'Relatório de avaliação de diabetes, recomendações nutricionais'),
  (3, '2024-10-03 09:30', 'Relatório psicológico: progresso, intervenções propostas');

-- Associar Trabalhadores a Relatórios
INSERT INTO SGA_TRABALHADOR_RELATORIO (id_trabalhador, id_relatorio) VALUES
  (1, 1),
  (3, 2),
  (4, 3);
