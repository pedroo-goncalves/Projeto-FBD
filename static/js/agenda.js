document.addEventListener('DOMContentLoaded', function () {

    // =========================================================
    // 1. REFERÊNCIAS
    // =========================================================
    const calendarEl = document.getElementById('calendar');

    const filtroMedico = document.getElementById('filtroMedico');
    const filtroPaciente = document.getElementById('filtroPaciente');
    const btnLimparFiltros = document.getElementById('btnLimparFiltros');

    const modalAgendamentoEl = document.getElementById('modalAgendamento');
    const inputData = document.getElementById('inputData');
    const selectHora = document.getElementById('selectHora');
    const selectMedico = document.getElementById('selectMedico');
    const checkOnline = document.getElementById('checkOnline');
    const selectDuracaoCriar = document.querySelector('#modalAgendamento select[name="duracao"]');

    const modalDetalhesEl = document.getElementById('modalDetalhes');
    const detalheId = document.getElementById('detalheId');
    const detalhePaciente = document.getElementById('detalhePaciente');
    const detalheMedico = document.getElementById('detalheMedico');
    const detalheIdMedico = document.getElementById('detalheIdMedico');
    const detalheData = document.getElementById('detalheData');
    const detalheDuracao = document.getElementById('detalheDuracao');
    const detalheHora = document.getElementById('detalheHora');

    // Referências do Registo Rápido (Secção 6)
    const btnNovoPaciente = document.getElementById('btnNovoPaciente');
    const formRapido = document.getElementById('formRapidoPaciente');
    const btnCancelarRapido = document.getElementById('btnCancelarRapido');
    const btnSalvarRapido = document.getElementById('btnSalvarRapido');
    const selectPacienteModal = document.getElementById('selectPaciente');

    // =========================================================
    // 2. CALENDÁRIO
    // =========================================================
    if (!calendarEl) return;

    const calendar = new FullCalendar.Calendar(calendarEl, {
        locale: 'pt',
        firstDay: 1,
        selectable: true,
        expandRows: true,
        allDaySlot: false,

        validRange: {
            start: new Date()
        },

        slotEventOverlap: false,

        initialView: 'dayGridMonth',

        headerToolbar: {
            left: 'prev,next today',
            center: 'title',
            right: 'dayGridMonth,timeGridWeek,timeGridDay'
        },

        navLinks: true,

        slotMinTime: '09:00:00',
        slotMaxTime: '18:00:00',
        slotDuration: '01:00:00',

        businessHours: [
            { daysOfWeek: [1, 2, 3, 4, 5], startTime: '09:00', endTime: '13:00' },
            { daysOfWeek: [1, 2, 3, 4, 5], startTime: '14:00', endTime: '18:00' }
        ],

        events: {
            url: '/api/eventos',
            extraParams: () => ({
                filtro_medico: filtroMedico?.value || '',
                filtro_paciente: filtroPaciente?.value || ''
            })
        },

        // 🔹 CLIQUE NO TEXTO DO DIA
        navLinkDayClick(date) {
            calendar.changeView('timeGridDay', date);
        },

        // 🔹 CLIQUE NAS CÉLULAS
        dateClick(info) {
            // MÊS → qualquer clique abre o dia
            if (info.view.type === 'dayGridMonth') {
                calendar.changeView('timeGridDay', info.dateStr);
                return;
            }

            // SEMANA/DIA → validar e abrir modal
            if (info.view.type === 'timeGridWeek' || info.view.type === 'timeGridDay') {
                if (!validarHorarioClique(info.date)) return;
                abrirModalCriar(info.dateStr);
            }
        },

        eventClick(info) {
            info.jsEvent.preventDefault();
            abrirModalDetalhes(info.event.extendedProps.num_atendimento || info.event.id);
        }
    });

    calendar.render();

    filtroMedico?.addEventListener('change', () => calendar.refetchEvents());
    filtroPaciente?.addEventListener('change', () => calendar.refetchEvents());

    btnLimparFiltros?.addEventListener('click', () => {
        if (filtroMedico) filtroMedico.value = '';
        if (filtroPaciente) filtroPaciente.value = '';
        calendar.refetchEvents();
    });

    // =========================================================
    // 3. VALIDAÇÃO
    // =========================================================
    function validarHorarioClique(dateObj) {
        const agora = new Date();
        const hojeZero = new Date(agora.getFullYear(), agora.getMonth(), agora.getDate());

        if (dateObj < hojeZero) return false;
        if ([0, 6].includes(dateObj.getDay())) return false;

        const h = dateObj.getHours();
        return !(h < 9 || h >= 18 || h === 13);
    }

    // =========================================================
    // 4. MODAL CRIAÇÃO
    // =========================================================
    function abrirModalCriar(dataString) {
        let dataFinal = dataString;
        let horaFinal = null;

        if (dataString.includes('T')) {
            [dataFinal, horaFinal] = dataString.split('T');
            horaFinal = horaFinal.substring(0, 5);
        }

        inputData.value = dataFinal;
        selectHora.innerHTML = '<option disabled selected>--:--</option>';
        selectHora.disabled = true;
        selectDuracaoCriar.value = "60";
        checkOnline.checked = false;

        carregarHorariosCriacao().then(() => {
            if (horaFinal) selectHora.value = horaFinal;
        });

        // Garantir que o formulário de novo paciente está escondido ao abrir o modal
        if (formRapido) formRapido.classList.add('d-none');

        new bootstrap.Modal(modalAgendamentoEl).show();
    }

    async function carregarHorariosCriacao() {
        if (!selectMedico.value || !inputData.value) return;

        const horaPreSelecionada = selectHora.value;

        try {
            const res = await fetch(
                `/api/horarios-disponiveis?medico=${selectMedico.value}&data=${inputData.value}&duracao=${selectDuracaoCriar.value}&is_online=${checkOnline.checked ? 1 : 0}`
            );
            const horarios = await res.json();

            selectHora.innerHTML = '<option disabled selected value="">--:--</option>';

            horarios.forEach(h => {
                const opt = document.createElement('option');
                opt.value = h;
                opt.textContent = h;
                if (h === horaPreSelecionada) {
                    opt.selected = true;
                }
                selectHora.appendChild(opt);
            });
            selectHora.disabled = false;
        } catch (e) {
            console.error("Erro ao carregar horários:", e);
        }
    }

    selectMedico?.addEventListener('change', carregarHorariosCriacao);
    selectDuracaoCriar?.addEventListener('change', carregarHorariosCriacao);
    checkOnline?.addEventListener('change', carregarHorariosCriacao);

    // =========================================================
    // 5. MODAL DETALHES
    // =========================================================
    function abrirModalDetalhes(id) {
        fetch(`/api/atendimento/${id}`)
            .then(res => res.json())
            .then(data => {
                detalheId.value = data.num_atendimento || data.id; // Tenta num_atendimento primeiro
                detalhePaciente.value = data.paciente;
                if (detalheMedico) detalheMedico.value = data.medico;
                detalheIdMedico.value = data.id_trabalhador || data.id_medico; // Tenta id_trabalhador
                detalheData.value = data.data_iso;

                // Calcular duração se não vier da API
                if (data.duracao) {
                    detalheDuracao.value = data.duracao;
                } else if (data.inicio_iso && data.fim_iso) {
                    // Fallback de cálculo
                    const start = new Date(data.inicio_iso);
                    const end = new Date(data.fim_iso);
                    const diffMins = (end - start) / 60000;
                    detalheDuracao.value = diffMins.toString();
                } else {
                    detalheDuracao.value = "60"; // Default
                }

                carregarHorariosEdicao(data.hora_iso);
                new bootstrap.Modal(modalDetalhesEl).show();
            })
            .catch(err => console.error("Erro detalhes:", err));
    }

    async function carregarHorariosEdicao(horaAtual = null) {
        if (!detalheIdMedico.value) return;

        try {
            const res = await fetch(
                `/api/horarios-disponiveis?medico=${detalheIdMedico.value}&data=${detalheData.value}&duracao=${detalheDuracao.value}&ignorar_id=${detalheId.value}`
            );
            const horarios = await res.json();

            detalheHora.innerHTML = '';
            horarios.forEach(h => {
                const opt = document.createElement('option');
                opt.value = h;
                opt.textContent = h;
                if (h === horaAtual) opt.selected = true;
                detalheHora.appendChild(opt);
            });
            detalheHora.disabled = false;
        } catch (e) {
            console.error(e);
        }
    }

    detalheData?.addEventListener('change', () => carregarHorariosEdicao(detalheHora.value || null));
    detalheDuracao?.addEventListener('change', () => carregarHorariosEdicao(detalheHora.value || null));


    // =========================================================
    // 6. REGISTO RÁPIDO DE PACIENTE (NOVO)
    // =========================================================

    // 1. Mostrar o formulário ao clicar no botão "+"
    if (btnNovoPaciente) {
        btnNovoPaciente.addEventListener('click', () => {
            formRapido.classList.remove('d-none');
        });
    }

    // 2. Esconder o formulário ao clicar em "Cancelar"
    if (btnCancelarRapido) {
        btnCancelarRapido.addEventListener('click', () => {
            formRapido.classList.add('d-none');
            const msgErro = document.getElementById('msgErroRapido');
            if (msgErro) msgErro.textContent = '';
        });
    }

    // 3. Enviar dados via AJAX ao clicar em "Guardar"
    if (btnSalvarRapido) {
        btnSalvarRapido.addEventListener('click', async () => {
            const nif = document.getElementById('newNif').value;
            const nome = document.getElementById('newNome').value;
            const tel = document.getElementById('newTel').value;
            const data = document.getElementById('newData').value;
            const msgErro = document.getElementById('msgErroRapido');

            if (!nif || !nome || !tel || !data) {
                if (msgErro) msgErro.textContent = 'Preencha todos os campos.';
                return;
            }

            try {
                const res = await fetch('/api/criar_paciente_rapido', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ nif, nome, telemovel: tel, data_nasc: data })
                });

                const json = await res.json();

                if (res.ok) {
                    // Sucesso: Adicionar o novo paciente ao dropdown e selecioná-lo
                    if (selectPacienteModal) {
                        const opt = document.createElement('option');
                        opt.value = json.nif; // O valor é o NIF
                        opt.textContent = `${json.nome} (${json.nif})`;
                        opt.selected = true;
                        selectPacienteModal.appendChild(opt);
                    }

                    // Limpar campos e esconder formulário
                    formRapido.classList.add('d-none');
                    document.getElementById('newNif').value = '';
                    document.getElementById('newNome').value = '';
                    document.getElementById('newTel').value = '';
                    document.getElementById('newData').value = '';
                    if (msgErro) msgErro.textContent = '';
                } else {
                    if (msgErro) msgErro.textContent = json.erro || 'Erro ao criar paciente.';
                }
            } catch (err) {
                console.error(err);
                if (msgErro) msgErro.textContent = 'Erro de comunicação.';
            }
        });
    }

});