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

    // --- Modal de DETALHES / EDIÇÃO ---
    const modalDetalhesEl = document.getElementById('modalDetalhes');
    const detalheId = document.getElementById('detalheId');
    const detalhePaciente = document.getElementById('detalhePaciente');
    const detalheMedico = document.getElementById('detalheMedico'); // Pode ser null se não for admin
    const detalheIdMedico = document.getElementById('detalheIdMedico');
    const detalheData = document.getElementById('detalheData');
    const detalheDuracao = document.getElementById('detalheDuracao');
    const detalheHora = document.getElementById('detalheHora');
    const badgeEstado = document.getElementById('badgeEstado');
    const btnCancelar = document.getElementById('btnCancelarConsulta');

    // =========================================================
    // VALIDAÇÃO DA DATA (MODAL CRIAR)
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
    // LIMPEZA DO MODAL AO ABRIR (MODAL CRIAR)
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
    // 2. CALENDÁRIO
    // =========================================================
    const urlParams = new URLSearchParams(window.location.search);
    const editId = urlParams.get('editar');
    const jumpDate = urlParams.get('data');

    if (calendarEl) {
        const calendar = new FullCalendar.Calendar(calendarEl, {
            initialView: sessionStorage.getItem('calendarView') || 'dayGridMonth',
            initialDate: jumpDate || sessionStorage.getItem('calendarDate') || new Date(),
            locale: 'pt',
            firstDay: 1, // Começa na Segunda-feira

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
                // Chama a função de detalhes agora implementada
                abrirModalDetalhes(info.event.extendedProps.num_atendimento || info.event.id);
            }
        });

        calendar.render();

        // Listeners dos Filtros
        filtroMedico?.addEventListener('change', () => calendar.refetchEvents());
        filtroPaciente?.addEventListener('change', () => calendar.refetchEvents());

        btnLimparFiltros?.addEventListener('click', () => {
            if (filtroMedico) filtroMedico.value = '';
            if (filtroPaciente) filtroPaciente.value = '';
            calendar.refetchEvents();
        });

        // Abrir modal automaticamente se vier link "editar=X"
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
        // Permite clicar apenas entre 9h-12h e 14h-17h
        return !(h < 9 || h >= 18 || h === 13);
    }

    // =========================================================
    // 3. FUNÇÕES: MODAL CRIAÇÃO
    // =========================================================
    function abrirModalCriar(dataString) {
        let dataFinal = dataString;
        let horaFinal = null;

        if (dataString.includes('T')) {
            [dataFinal, horaFinal] = dataString.split('T');
            horaFinal = horaFinal.substring(0, 5);
        }

        if (inputData) inputData.value = dataFinal;
        if (selectDuracaoCriar) selectDuracaoCriar.value = "60";

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
                const opt = document.createElement('option');
                opt.disabled = true;
                opt.text = 'Sem vagas';
                selectHora.appendChild(opt);
            } else {
                horarios.forEach(hora => {
                    // Se for hoje, filtrar horas já passadas
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

    // Listeners Modal Criação
    selectMedico?.addEventListener('change', carregarHorariosCriacao);
    checkOnline?.addEventListener('change', carregarHorariosCriacao);
    selectDuracaoCriar?.addEventListener('change', carregarHorariosCriacao);


    // =========================================================
    // 4. FUNÇÕES: MODAL DETALHES / EDIÇÃO
    // =========================================================
    function abrirModalDetalhes(id) {

        // 1. Buscar dados à API
        fetch(`/api/atendimento/${id}`)
            .then(res => res.json())
            .then(data => {
                if (data.erro) {
                    alert(data.erro);
                    return;
                }

                // 2. Preencher o Modal
                if (detalheId) detalheId.value = data.id;
                if (detalhePaciente) detalhePaciente.value = data.paciente;

                // Se for admin, mostra o nome do médico
                if (detalheMedico) detalheMedico.value = data.medico;

                // Guardar ID médico (essencial para calcular disponibilidade na edição)
                if (detalheIdMedico) detalheIdMedico.value = data.id_medico;

                // Preencher Data e Duração atuais
                if (detalheData) detalheData.value = data.data_iso;
                if (detalheDuracao) detalheDuracao.value = data.duracao;

                // Atualizar Badge de Estado
                if (badgeEstado) {
                    badgeEstado.textContent = data.estado;
                    if (data.estado === 'agendado') {
                        badgeEstado.className = 'badge bg-success bg-opacity-75 shadow-sm badge-estado';
                    } else {
                        badgeEstado.className = 'badge bg-secondary bg-opacity-75 shadow-sm badge-estado';
                    }
                }

                // Configurar Botão de Cancelar
                if (btnCancelar) {
                    btnCancelar.href = `/cancelar_agendamento/${data.id}`;
                    // Se já estiver cancelado, bloqueia botão
                    if (data.estado === 'cancelado') {
                        btnCancelar.classList.add('disabled');
                        btnCancelar.style.pointerEvents = 'none';
                    } else {
                        btnCancelar.classList.remove('disabled');
                        btnCancelar.style.pointerEvents = 'auto';
                    }
                }

                // 3. Carregar Slots Livres para Edição (preservando a hora atual)
                carregarHorariosEdicao(data.hora_iso);

                // 4. Mostrar Modal
                new bootstrap.Modal(modalDetalhesEl).show();
            })
            .catch(err => console.error("Erro ao carregar detalhes:", err));
    }

    async function carregarHorariosEdicao(horaAtualSelecionada = null) {
        if (!detalheIdMedico || !detalheData || !detalheHora) return;
        if (!detalheIdMedico.value || !detalheData.value) return;

        const idMedico = detalheIdMedico.value;
        const dataVal = detalheData.value;
        const duracao = detalheDuracao ? detalheDuracao.value : 60;
        const idAtendimento = detalheId.value; // Importante: Ignorar a própria consulta na verificação

        detalheHora.innerHTML = '<option>A verificar...</option>';
        detalheHora.disabled = true;

        try {
            // Chama a API com o parâmetro extra 'ignorar_id' para não bloquear a própria vaga
            const res = await fetch(`/api/horarios-disponiveis?medico=${idMedico}&data=${dataVal}&duracao=${duracao}&ignorar_id=${idAtendimento}`);
            const horarios = await res.json();

            detalheHora.innerHTML = '';

            if (horarios.length === 0) {
                const opt = document.createElement('option');
                opt.disabled = true;
                opt.text = 'Sem vagas';
                detalheHora.appendChild(opt);
            } else {
                let currentSelected = false;

                horarios.forEach(hora => {
                    const opt = document.createElement('option');
                    opt.value = hora;
                    opt.textContent = hora;

                    // Se esta for a hora que a consulta já tem, seleciona-a
                    if (hora === horaAtualSelecionada) {
                        opt.selected = true;
                        currentSelected = true;
                    }
                    detalheHora.appendChild(opt);
                });

                // Se a hora atual não estiver na lista (ex: mudou duração e deixou de caber), 
                // o user terá de escolher outra.

                detalheHora.disabled = false;
            }
        } catch (error) {
            console.error(error);
            detalheHora.innerHTML = '<option>Erro ao carregar</option>';
        }
    }

    // Listeners: Atualizar horários se mudarmos a data ou duração na edição
    if (detalheData) {
        detalheData.addEventListener('change', () => carregarHorariosEdicao());
    }
    if (detalheDuracao) {
        detalheDuracao.addEventListener('change', () => carregarHorariosEdicao());
    }

});