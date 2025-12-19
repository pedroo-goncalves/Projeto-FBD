document.addEventListener('DOMContentLoaded', function () {
    const medicoInput = document.getElementById('selectMedico'); // Pode ser Select ou Hidden
    const dataInput = document.getElementById('inputData');
    const horaSelect = document.getElementById('selectHora');

    // Configurar data mínima como hoje
    if (dataInput) {
        dataInput.min = new Date().toISOString().split("T")[0];
    }

    async function carregarHorarios() {
        // Se for hidden input (colaborador), value já lá está. Se for select, pega o selecionado.
        const medicoId = medicoInput.value;
        const dataVal = dataInput.value;

        // Só faz pedido se ambos estiverem preenchidos
        if (medicoId && dataVal) {
            horaSelect.innerHTML = '<option>A verificar disponibilidade...</option>';
            horaSelect.disabled = true;

            try {
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
                console.error('Erro:', error);
                horaSelect.innerHTML = '<option>Erro ao carregar</option>';
            }
        }
    }

    // Adicionar Listeners
    if (medicoInput && dataInput) {
        // Se for um SELECT (Admin), ouve mudanças. Se for Hidden (Médico), não precisa de listener (valor fixo)
        if (medicoInput.tagName === 'SELECT') {
            medicoInput.addEventListener('change', carregarHorarios);
        }

        dataInput.addEventListener('change', carregarHorarios);

        // Se o médico já estiver preenchido (Colaborador) e o user escolher a data, dispara logo
        if (medicoInput.value && dataInput.value) {
            carregarHorarios();
        }
    }
});