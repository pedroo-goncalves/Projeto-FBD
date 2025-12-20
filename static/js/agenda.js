document.addEventListener('DOMContentLoaded', function () {

    // =========================================================
    // PARTE 1: LÓGICA DE CARREGAR HORÁRIOS
    // =========================================================
    const medicoInput = document.getElementById('selectMedico'); // Pode ser Select ou Hidden
    const dataInput = document.getElementById('inputData');
    const horaSelect = document.getElementById('selectHora');

    // Configurar data mínima como hoje
    if (dataInput) {
        dataInput.min = new Date().toISOString().split("T")[0];
    }

    async function carregarHorarios() {
        const medicoId = medicoInput ? medicoInput.value : null;
        const dataVal = dataInput ? dataInput.value : null;

        // Só faz pedido se ambos estiverem preenchidos
        if (medicoId && dataVal) {
            horaSelect.innerHTML = '<option>A verificar disponibilidade...</option>';
            horaSelect.disabled = true;

            try {
                // Faz o pedido à API
                const response = await fetch(`/api/horarios-disponiveis?medico=${medicoId}&data=${dataVal}`);
                const horarios = await response.json();

                horaSelect.innerHTML = '<option value="" selected disabled>Escolha um horário</option>';

                if (horarios.length === 0) {
                    horaSelect.innerHTML += '<option disabled>Sem vagas para este dia</option>';
                } else {
                    horarios.forEach(hora => {
                        const option = document.createElement('option');
                        option.value = hora;
                        option.textContent = hora;
                        horaSelect.appendChild(option);
                    });
                    horaSelect.disabled = false;
                }
            } catch (error) {
                console.error('Erro ao carregar horários:', error);
                horaSelect.innerHTML = '<option>Erro de ligação</option>';
            }
        }
    }

    // ADICIONAR OS LISTENERS (Eventos)
    if (medicoInput && dataInput) {
        // Se for Select (Admin), atualiza ao mudar. Se for Hidden (Médico), não faz nada.
        if (medicoInput.tagName === 'SELECT') {
            medicoInput.addEventListener('change', carregarHorarios);
        }

        // 'input' dispara logo que a data muda (melhor que 'change')
        dataInput.addEventListener('input', carregarHorarios);
        dataInput.addEventListener('change', carregarHorarios); // Redundância segura

        // Se já tiver dados preenchidos ao abrir (ex: refresh), carrega logo
        if (medicoInput.value && dataInput.value) {
            carregarHorarios();
        }
    }


    // =========================================================
    // PARTE 2: LÓGICA DE NOVO PACIENTE RÁPIDO
    // =========================================================
    const btnNovo = document.getElementById('btnNovoPaciente');
    const formRapido = document.getElementById('formRapidoPaciente');
    const btnCancelar = document.getElementById('btnCancelarRapido');
    const btnSalvar = document.getElementById('btnSalvarRapido');
    const selectPaciente = document.getElementById('selectPaciente');
    const msgErro = document.getElementById('msgErroRapido');

    // Só ativa esta parte se os elementos existirem na página
    if (btnNovo && formRapido) {

        // 1. Mostrar Form
        btnNovo.addEventListener('click', () => {
            formRapido.classList.remove('d-none');
            btnNovo.disabled = true;
        });

        // 2. Esconder Form
        btnCancelar.addEventListener('click', () => {
            formRapido.classList.add('d-none');
            btnNovo.disabled = false;
            msgErro.textContent = '';
            limparCampos();
        });

        // 3. Enviar Dados (AJAX)
        btnSalvar.addEventListener('click', async () => {
            const dados = {
                nif: document.getElementById('newNif').value,
                nome: document.getElementById('newNome').value,
                telemovel: document.getElementById('newTel').value,
                data_nasc: document.getElementById('newData').value
            };

            if (!dados.nif || !dados.nome || !dados.telemovel || !dados.data_nasc) {
                msgErro.textContent = 'Preencha todos os campos.';
                return;
            }

            try {
                btnSalvar.textContent = 'A guardar...';
                btnSalvar.disabled = true;

                const response = await fetch('/api/criar_paciente_rapido', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(dados)
                });

                const result = await response.json();

                if (response.ok) {
                    // SUCESSO!
                    // Cria a nova opção no Select e seleciona-a
                    // Usamos o NIF como value porque é isso que o backend espera no form de agendamento
                    const novaOpcao = document.createElement('option');
                    novaOpcao.value = result.nif;
                    novaOpcao.textContent = `${result.nome} (${result.nif})`;
                    novaOpcao.selected = true;

                    selectPaciente.appendChild(novaOpcao);

                    // Reset à interface
                    formRapido.classList.add('d-none');
                    btnNovo.disabled = false;
                    limparCampos();

                    // Pequeno feedback visual no select
                    selectPaciente.classList.add('is-valid');
                    setTimeout(() => selectPaciente.classList.remove('is-valid'), 2000);

                } else {
                    msgErro.textContent = result.erro || 'Erro ao guardar.';
                }

            } catch (error) {
                console.error(error);
                msgErro.textContent = 'Erro de ligação ao servidor.';
            } finally {
                btnSalvar.textContent = 'Guardar & Selecionar';
                btnSalvar.disabled = false;
            }
        });

        function limparCampos() {
            document.getElementById('newNif').value = '';
            document.getElementById('newNome').value = '';
            document.getElementById('newTel').value = '';
            document.getElementById('newData').value = '';
        }
    }
});