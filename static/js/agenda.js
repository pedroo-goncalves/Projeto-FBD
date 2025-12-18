document.addEventListener('DOMContentLoaded', function () {
    // ids do teu modal
    const medicoSelect = document.getElementById('selectMedico');
    const dataInput = document.getElementById('inputData');
    const horaSelect = document.getElementById('selectHora');

    // Configurar data mínima como hoje
    const hoje = new Date().toISOString().split("T")[0];
    dataInput.setAttribute('min', hoje);

    async function carregarHorarios() {
        const medicoId = medicoSelect.value;
        const dataVal = dataInput.value;

        // Só faz pedido se ambos estiverem preenchidos
        if (medicoId && dataVal) {
            // UI de carregamento
            horaSelect.innerHTML = '<option>A carregar vagas...</option>';
            horaSelect.disabled = true;

            try {
                // Chama a tua API Python
                const response = await fetch(`/api/horarios-disponiveis?medico=${medicoId}&data=${dataVal}`);
                const horarios = await response.json();

                // Limpa
                horaSelect.innerHTML = '<option value="" selected disabled>Selecione um horário</option>';

                if (horarios.length === 0) {
                    horaSelect.innerHTML += '<option disabled>Sem vagas neste dia</option>';
                } else {
                    // Preenche as opções
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

    // Adicionar Event Listeners
    if (medicoSelect && dataInput) {
        medicoSelect.addEventListener('change', carregarHorarios);
        dataInput.addEventListener('change', carregarHorarios);
    }
});