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

        // --- CORREÇÃO VISUAL PARA ADMIN ---
        slotEventOverlap: false, // Isto impede que fiquem uns em cima dos outros
        // ----------------------------------

        initialView: 'dayGridMonth',

        headerToolbar: {
            left: 'prev,next today',
            center: 'title',
            right: 'dayGridMonth,timeGridWeek,timeGridDay'
        },

        // 🔹 torna o texto do dia clicável
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

        // =====================================================
        // 🔹 CLIQUE NO TEXTO DO DIA (Week / Month)
        // =====================================================
        navLinkDayClick(date) {
            calendar.changeView('timeGridDay', date);
        },

        // =====================================================
        // 🔹 CLIQUE NAS CÉLULAS
        // =====================================================
        dateClick(info) {

            // MÊS → qualquer clique abre o dia
            if (info.view.type === 'dayGridMonth') {
                calendar.changeView('timeGridDay', info.dateStr);
                return;
            }

            // SEMANA → clicar numa hora cria consulta
            if (info.view.type === 'timeGridWeek') {
                if (!validarHorarioClique(info.date)) return;
                abrirModalCriar(info.dateStr);
                return;
            }

            // DIA → comportamento normal
            if (info.view.type === 'timeGridDay') {
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
        filtroMedico.value = '';
        filtroPaciente.value = '';
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

        new bootstrap.Modal(modalAgendamentoEl).show();
    }

    async function carregarHorariosCriacao() {
        if (!selectMedico.value || !inputData.value) return;

        // 1. Guardar a hora que estava selecionada antes de limpar
        const horaPreSelecionada = selectHora.value;

        const res = await fetch(
            `/api/horarios-disponiveis?medico=${selectMedico.value}&data=${inputData.value}&duracao=${selectDuracaoCriar.value}&is_online=${checkOnline.checked ? 1 : 0}`
        );

        const horarios = await res.json();

        // Limpar e reconstruir
        selectHora.innerHTML = '<option disabled selected value="">--:--</option>';

        let manteveSelecao = false;

        horarios.forEach(h => {
            const opt = document.createElement('option');
            opt.value = h;
            opt.textContent = h;

            // 2. Se a nova hora for igual à que estava selecionada, volta a marcar
            if (h === horaPreSelecionada) {
                opt.selected = true;
                manteveSelecao = true;
            }

            selectHora.appendChild(opt);
        });

        // Se a hora antiga já não é válida (ex: 12:00 cabe para 1h, mas não para 2h por causa do almoço), 
        // o 'value' fica vazio (o option disabled selected inicial).

        selectHora.disabled = false;
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
                detalheId.value = data.id;
                detalhePaciente.value = data.paciente;
                if (detalheMedico) detalheMedico.value = data.medico;
                detalheIdMedico.value = data.id_medico;
                detalheData.value = data.data_iso;
                detalheDuracao.value = data.duracao;

                carregarHorariosEdicao(data.hora_iso);
                new bootstrap.Modal(modalDetalhesEl).show();
            });
    }

    async function carregarHorariosEdicao(horaAtual = null) {
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
    }

    detalheData?.addEventListener('change', () => carregarHorariosEdicao(detalheHora.value || null));
    detalheDuracao?.addEventListener('change', () => carregarHorariosEdicao(detalheHora.value || null));

});