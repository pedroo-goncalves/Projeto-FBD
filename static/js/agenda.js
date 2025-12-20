document.addEventListener('DOMContentLoaded', function () {

    // =========================================================
    // 1. REFERÊNCIAS
    // =========================================================
    const calendarEl = document.getElementById('calendar');

    // Modal e Inputs
    const modalEl = document.getElementById('modalAgendamento');
    const inputData = document.getElementById('inputData');
    const selectHora = document.getElementById('selectHora');
    const selectMedico = document.getElementById('selectMedico');
    const checkOnline = document.getElementById('checkOnline');

    // Paciente Rápido
    const btnNovo = document.getElementById('btnNovoPaciente');
    const formRapido = document.getElementById('formRapidoPaciente');
    const btnCancelar = document.getElementById('btnCancelarRapido');
    const btnSalvar = document.getElementById('btnSalvarRapido');
    const selectPaciente = document.getElementById('selectPaciente');
    const msgErro = document.getElementById('msgErroRapido');

    // =========================================================
    // 2. CONFIGURAÇÃO DO CALENDÁRIO
    // =========================================================
    if (calendarEl) {
        const calendar = new FullCalendar.Calendar(calendarEl, {
            initialView: sessionStorage.getItem('calendarView') || 'dayGridMonth',
            initialDate: sessionStorage.getItem('calendarDate') || new Date(),
            locale: 'pt',
            firstDay: 1,

            datesSet: function (info) {
                sessionStorage.setItem('calendarView', info.view.type);
                sessionStorage.setItem('calendarDate', info.view.currentStart.toISOString());
            },

            // --- VISUAL LIMPO (09:00 - 18:00) ---
            slotMinTime: '09:00:00', // Esconde tudo antes das 09h
            slotMaxTime: '18:00:00', // Esconde tudo depois das 18h

            slotDuration: '01:00:00',   // Linhas de 1 hora
            slotLabelInterval: '01:00', // Etiquetas de hora a hora
            allDaySlot: false,          // Remove linha "Dia Todo"
            expandRows: true,           // Estica para ocupar o ecrã

            headerToolbar: {
                left: 'prev,next today',
                center: 'title',
                right: 'dayGridMonth,timeGridWeek'
            },

            // --- TRUQUE DO ALMOÇO CINZENTO ---
            // Definimos dois blocos de trabalho. O "buraco" (13h-14h) fica cinzento.
            businessHours: [
                {
                    // Manhã (09:00 - 13:00)
                    daysOfWeek: [1, 2, 3, 4, 5],
                    startTime: '09:00',
                    endTime: '13:00'
                },
                {
                    // Tarde (14:00 - 18:00)
                    daysOfWeek: [1, 2, 3, 4, 5],
                    startTime: '14:00',
                    endTime: '18:00'
                }
            ],

            // Fonte de dados
            events: '/api/eventos',

            // Interações
            navLinks: true,
            selectable: true,

            // --- CLICK ---
            dateClick: function (info) {
                if (!validarHorarioClique(info.date, info.view.type)) {
                    return; // Bloqueia clique no almoço ou fim de semana
                }
                abrirModalSmart(info.dateStr);
            },

            eventClick: function (info) {
                // Opcional
            }
        });

        calendar.render();
    }

    // =========================================================
    // VALIDAÇÃO DE HORÁRIO (AGORA BLOQUEIA AS 13H TAMBÉM)
    // =========================================================
    function validarHorarioClique(dateObj, viewType) {
        const diaSemana = dateObj.getDay(); // 0=Domingo, 6=Sábado

        // 1. Bloquear Fins de Semana
        if (diaSemana === 0 || diaSemana === 6) return false;

        // 2. Se for MÊS, deixa passar (ignora horas)
        if (viewType === 'dayGridMonth') return true;

        // 3. Se for SEMANA, valida horas
        const hora = dateObj.getHours();

        // Bloqueia almoço (13h)
        if (hora === 13) return false;

        // O slotMinTime já esconde o resto visualmente, mas por segurança:
        if (hora < 9 || hora >= 18) return false;

        return true;
    }

    // =========================================================
    // 3. ABRIR MODAL
    // =========================================================
    function abrirModalSmart(dataString) {
        if (!inputData || !modalEl) return;

        let dataFinal = dataString;
        let horaFinal = null;

        if (dataString.includes('T')) {
            const partes = dataString.split('T');
            dataFinal = partes[0];
            horaFinal = partes[1].substring(0, 5);
        }

        inputData.value = dataFinal;
        inputData.dispatchEvent(new Event('input'));

        const modal = new bootstrap.Modal(modalEl);
        modal.show();

        if (horaFinal && selectHora) {
            selectHora.innerHTML = '<option>A carregar...</option>';
            setTimeout(() => {
                let existe = Array.from(selectHora.options).some(opt => opt.value === horaFinal);
                if (existe) {
                    selectHora.value = horaFinal;
                    selectHora.classList.add('is-valid');
                    setTimeout(() => selectHora.classList.remove('is-valid'), 1000);
                }
            }, 600);
        }
    }

    // =========================================================
    // 4. CARREGAR HORÁRIOS (API)
    // =========================================================
    async function carregarHorarios() {
        const medicoId = selectMedico ? selectMedico.value : null;
        const dataVal = inputData ? inputData.value : null;
        const isOnline = checkOnline && checkOnline.checked ? 1 : 0;

        if (medicoId && dataVal) {
            selectHora.innerHTML = '<option>A verificar...</option>';
            selectHora.disabled = true;

            try {
                const url = `/api/horarios-disponiveis?medico=${medicoId}&data=${dataVal}&is_online=${isOnline}`;
                const response = await fetch(url);
                const horarios = await response.json();

                selectHora.innerHTML = '<option value="" selected disabled>Escolha um horário</option>';

                if (horarios.length === 0) {
                    selectHora.innerHTML += '<option disabled>Indisponível</option>';
                } else {
                    horarios.forEach(hora => {
                        const option = document.createElement('option');
                        option.value = hora;
                        option.textContent = hora;
                        selectHora.appendChild(option);
                    });
                    selectHora.disabled = false;
                }
            } catch (error) {
                console.error(error);
                selectHora.innerHTML = '<option>Erro</option>';
            }
        }
    }

    if (selectMedico) selectMedico.addEventListener('change', carregarHorarios);
    if (inputData) inputData.addEventListener('input', carregarHorarios);
    if (checkOnline) checkOnline.addEventListener('change', carregarHorarios);

    // =========================================================
    // 5. PACIENTE RÁPIDO
    // =========================================================
    if (btnNovo && formRapido) {
        btnNovo.addEventListener('click', () => {
            formRapido.classList.remove('d-none');
            btnNovo.disabled = true;
        });

        btnCancelar.addEventListener('click', () => {
            formRapido.classList.add('d-none');
            btnNovo.disabled = false;
            msgErro.textContent = '';
            limparCamposRapido();
        });

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
                    const novaOpcao = document.createElement('option');
                    novaOpcao.value = result.nif;
                    novaOpcao.textContent = `${result.nome} (${result.nif})`;
                    novaOpcao.selected = true;
                    selectPaciente.appendChild(novaOpcao);

                    formRapido.classList.add('d-none');
                    btnNovo.disabled = false;
                    limparCamposRapido();

                } else {
                    msgErro.textContent = result.erro || 'Erro ao guardar.';
                }
            } catch (error) {
                msgErro.textContent = 'Erro de ligação.';
            } finally {
                btnSalvar.textContent = 'Guardar';
                btnSalvar.disabled = false;
            }
        });

        function limparCamposRapido() {
            document.getElementById('newNif').value = '';
            document.getElementById('newNome').value = '';
            document.getElementById('newTel').value = '';
            document.getElementById('newData').value = '';
        }
    }
});