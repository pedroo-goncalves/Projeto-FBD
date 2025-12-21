document.addEventListener('DOMContentLoaded', function () {

    // =========================================================
    // 1. REFERÊNCIAS GERAIS AO DOM
    // =========================================================
    const calendarEl = document.getElementById('calendar');

    // --- Filtros ---
    const filtroMedico = document.getElementById('filtroMedico');
    const filtroPaciente = document.getElementById('filtroPaciente');
    const btnLimparFiltros = document.getElementById('btnLimparFiltros');

    // --- Modal de CRIAÇÃO ---
    const modalAgendamentoEl = document.getElementById('modalAgendamento');
    const inputData = document.getElementById('inputData');
    const selectHora = document.getElementById('selectHora');
    const selectMedico = document.getElementById('selectMedico');
    const checkOnline = document.getElementById('checkOnline');
    const selectPaciente = document.getElementById('selectPaciente');
    const selectDuracaoCriar = document.querySelector('#modalAgendamento select[name="duracao"]');
    const btnGlobal = document.getElementById('btnNovoAgendamentoGlobal');

    // =========================================================
    // VALIDAÇÃO DA DATA (CORRIGIDA – ESCREVER OU PICKER)
    // =========================================================
    if (inputData) {

        const hoje = new Date();
        hoje.setHours(0, 0, 0, 0);
        inputData.min = hoje.toISOString().split('T')[0];

        inputData.addEventListener('change', function () {
            if (!this.value) return;

            const data = new Date(this.value + 'T00:00:00');
            const diaSemana = data.getDay(); // 0 = Domingo | 6 = Sábado

            // Bloquear dias passados
            if (data < hoje) {
                this.setCustomValidity('Não é possível agendar consultas em dias passados.');
                this.reportValidity();
                this.value = '';
                resetHorasCriacao();
                return;
            }

            // Bloquear fins de semana
            if (diaSemana === 0 || diaSemana === 6) {
                this.setCustomValidity('As consultas apenas podem ser agendadas em dias úteis (Seg-Sex).');
                this.reportValidity();
                this.value = '';
                resetHorasCriacao();
                return;
            }

            // Data válida
            this.setCustomValidity('');
            carregarHorariosCriacao();
        });
    }

    function resetHorasCriacao() {
        if (!selectHora) return;
        selectHora.innerHTML = '<option disabled selected>--:--</option>';
        selectHora.disabled = true;
    }

    // =========================================================
    // LIMPEZA DO MODAL AO ABRIR
    // =========================================================
    if (btnGlobal) {
        btnGlobal.addEventListener('click', function () {

            if (inputData) inputData.value = '';

            if (selectHora) {
                selectHora.innerHTML = '<option value="" selected disabled>--:--</option>';
                selectHora.disabled = true;
                selectHora.classList.remove('is-valid');
            }

            if (selectDuracaoCriar) selectDuracaoCriar.value = "60";
            if (checkOnline) checkOnline.checked = false;
        });
    }

    // =========================================================
    // 2. CALENDÁRIO (INALTERADO)
    // =========================================================
    const urlParams = new URLSearchParams(window.location.search);
    const editId = urlParams.get('editar');
    const jumpDate = urlParams.get('data');

    if (calendarEl) {
        const calendar = new FullCalendar.Calendar(calendarEl, {
            initialView: sessionStorage.getItem('calendarView') || 'dayGridMonth',
            initialDate: jumpDate || sessionStorage.getItem('calendarDate') || new Date(),
            locale: 'pt',
            firstDay: 1,

            validRange: {
                start: new Date()
            },

            datesSet: function (info) {
                sessionStorage.setItem('calendarView', info.view.type);
                sessionStorage.setItem('calendarDate', info.view.currentStart.toISOString());
            },

            slotMinTime: '09:00:00',
            slotMaxTime: '18:00:00',
            slotDuration: '01:00:00',
            allDaySlot: false,
            expandRows: true,

            headerToolbar: {
                left: 'prev,next today',
                center: 'title',
                right: 'dayGridMonth,timeGridWeek'
            },

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

            selectable: true,

            dateClick(info) {
                if (!validarHorarioClique(info.date, info.view.type)) return;
                abrirModalCriar(info.dateStr);
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

        if (editId) {
            setTimeout(() => {
                abrirModalDetalhes(editId);
                window.history.replaceState({}, document.title, "/agenda");
            }, 500);
        }
    }

    function validarHorarioClique(dateObj, viewType) {

        const agora = new Date();
        const hojeZero = new Date(agora.getFullYear(), agora.getMonth(), agora.getDate());

        if (dateObj < hojeZero) return false;

        const dia = dateObj.getDay();
        if (dia === 0 || dia === 6) return false;

        if (viewType === 'dayGridMonth') return true;

        const h = dateObj.getHours();
        return !(h < 9 || h >= 18 || h === 13);
    }

    // =========================================================
    // 3. MODAL CRIAÇÃO
    // =========================================================
    function abrirModalCriar(dataString) {
        let dataFinal = dataString;
        let horaFinal = null;

        if (dataString.includes('T')) {
            [dataFinal, horaFinal] = dataString.split('T');
            horaFinal = horaFinal.substring(0, 5);
        }

        inputData.value = dataFinal;
        selectDuracaoCriar.value = "60";

        carregarHorariosCriacao().then(() => {
            if (horaFinal && selectHora) selectHora.value = horaFinal;
        });

        new bootstrap.Modal(modalAgendamentoEl).show();
    }

    async function carregarHorariosCriacao() {
        if (!selectHora) return;

        const medicoId = selectMedico.value;
        const dataVal = inputData.value;
        const isOnline = checkOnline.checked ? 1 : 0;
        const duracao = selectDuracaoCriar.value;

        if (!medicoId || !dataVal) {
            resetHorasCriacao();
            return;
        }

        const agora = new Date();
        const hojeISO = agora.toISOString().split('T')[0];
        const minutosAgora = agora.getHours() * 60 + agora.getMinutes();

        selectHora.innerHTML = '<option>A verificar...</option>';
        selectHora.disabled = true;

        try {
            const res = await fetch(`/api/horarios-disponiveis?medico=${medicoId}&data=${dataVal}&is_online=${isOnline}&duracao=${duracao}`);
            const horarios = await res.json();

            selectHora.innerHTML = '<option disabled selected>--:--</option>';

            if (horarios.length === 0) {
                selectHora.innerHTML = '<option disabled>Sem vagas</option>';
            } else {
                horarios.forEach(hora => {

                    if (dataVal === hojeISO) {
                        const [h, m] = hora.split(':').map(Number);
                        if (h * 60 + m <= minutosAgora) return;
                    }

                    const opt = document.createElement('option');
                    opt.value = hora;
                    opt.textContent = hora;
                    selectHora.appendChild(opt);
                });

                selectHora.disabled = false;
            }

        } catch {
            selectHora.innerHTML = '<option>Erro</option>';
        }
    }

    selectMedico?.addEventListener('change', carregarHorariosCriacao);
    checkOnline?.addEventListener('change', carregarHorariosCriacao);
    selectDuracaoCriar?.addEventListener('change', carregarHorariosCriacao);

});
