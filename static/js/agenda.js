document.addEventListener('DOMContentLoaded', function () {

    // =========================================================
    // 1. REFERÊNCIAS GERAIS
    // =========================================================
    const calendarEl = document.getElementById('calendar');

    // --- Modal de CRIAÇÃO ---
    const modalAgendamentoEl = document.getElementById('modalAgendamento');
    const inputData = document.getElementById('inputData');
    const selectHora = document.getElementById('selectHora');
    const selectMedico = document.getElementById('selectMedico');
    const checkOnline = document.getElementById('checkOnline');
    const selectDuracaoCriar = document.querySelector('#modalAgendamento select[name="duracao"]');

    // --- Modal de EDIÇÃO ---
    const modalDetalhesEl = document.getElementById('modalDetalhes');
    const detalheId = document.getElementById('detalheId');
    const detalheData = document.getElementById('detalheData');
    const detalheHora = document.getElementById('detalheHora');
    const detalheDuracao = document.getElementById('detalheDuracao');
    const detalheIdMedico = document.getElementById('detalheIdMedico');
    const badge = document.getElementById('badgeEstado');
    const inpPaciente = document.getElementById('detalhePaciente');
    const inpMedico = document.getElementById('detalheMedico'); // Pode ser NULL se não for admin
    const btnCancel = document.getElementById('btnCancelarConsulta');

    // Variável de memória
    let horaOriginalEdicao = null;

    // --- Paciente Rápido ---
    const btnNovo = document.getElementById('btnNovoPaciente');
    const formRapido = document.getElementById('formRapidoPaciente');
    const btnCancelar = document.getElementById('btnCancelarRapido');
    const btnSalvar = document.getElementById('btnSalvarRapido');
    const selectPaciente = document.getElementById('selectPaciente');
    const msgErro = document.getElementById('msgErroRapido');


    // =========================================================
    // 2. CONFIG CALENDÁRIO
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

            slotMinTime: '09:00:00',
            slotMaxTime: '18:00:00',
            slotDuration: '01:00:00',
            slotLabelInterval: '01:00',
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

            events: '/api/eventos',
            navLinks: true,
            selectable: true,

            dateClick: function (info) {
                if (!validarHorarioClique(info.date, info.view.type)) return;
                abrirModalCriar(info.dateStr);
            },

            eventClick: function (info) {
                info.jsEvent.preventDefault();
                const idAtendimento = info.event.extendedProps.num_atendimento || info.event.id;
                abrirModalDetalhes(idAtendimento);
            }
        });
        calendar.render();
    }

    function validarHorarioClique(dateObj, viewType) {
        const diaSemana = dateObj.getDay();
        if (diaSemana === 0 || diaSemana === 6) return false;
        if (viewType === 'dayGridMonth') return true;

        const hora = dateObj.getHours();
        if (hora === 13) return false;
        if (hora < 9 || hora >= 18) return false;
        return true;
    }


    // =========================================================
    // 3. MODAL CRIAÇÃO
    // =========================================================
    function abrirModalCriar(dataString) {
        if (!inputData || !modalAgendamentoEl) return;

        let dataFinal = dataString;
        let horaFinal = null;

        if (dataString.includes('T')) {
            const partes = dataString.split('T');
            dataFinal = partes[0];
            horaFinal = partes[1].substring(0, 5);
        }

        inputData.value = dataFinal;
        if (selectDuracaoCriar) selectDuracaoCriar.value = "60";

        carregarHorariosCriacao().then(() => {
            if (horaFinal && selectHora) {
                setTimeout(() => {
                    let existe = Array.from(selectHora.options).some(opt => opt.value === horaFinal);
                    if (existe) {
                        selectHora.value = horaFinal;
                        selectHora.classList.add('is-valid');
                        setTimeout(() => selectHora.classList.remove('is-valid'), 1000);
                    }
                }, 100);
            }
        });

        const modal = new bootstrap.Modal(modalAgendamentoEl);
        modal.show();
    }

    async function carregarHorariosCriacao() {
        const medicoId = selectMedico ? selectMedico.value : null;
        const dataVal = inputData ? inputData.value : null;
        const isOnline = checkOnline && checkOnline.checked ? 1 : 0;
        const duracao = selectDuracaoCriar ? selectDuracaoCriar.value : 60;

        if (medicoId && dataVal) {
            selectHora.innerHTML = '<option>A verificar...</option>';
            selectHora.disabled = true;

            try {
                const url = `/api/horarios-disponiveis?medico=${medicoId}&data=${dataVal}&is_online=${isOnline}&duracao=${duracao}`;
                const response = await fetch(url);
                const horarios = await response.json();

                selectHora.innerHTML = '<option value="" selected disabled>--:--</option>';

                if (horarios.length === 0) {
                    selectHora.innerHTML += '<option disabled>Sem vagas</option>';
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

    if (selectMedico) selectMedico.addEventListener('change', carregarHorariosCriacao);
    if (inputData) inputData.addEventListener('input', carregarHorariosCriacao);
    if (checkOnline) checkOnline.addEventListener('change', carregarHorariosCriacao);
    if (selectDuracaoCriar) selectDuracaoCriar.addEventListener('change', carregarHorariosCriacao);


    // =========================================================
    // 4. MODAL EDIÇÃO
    // =========================================================
    async function abrirModalDetalhes(id) {
        if (!modalDetalhesEl) return;

        try {
            const response = await fetch(`/api/atendimento/${id}`);
            const dados = await response.json();

            if (response.ok) {
                detalheId.value = dados.id;
                inpPaciente.value = dados.paciente;

                // PROTEÇÃO: Só preenche o médico se o campo existir (se for admin)
                if (inpMedico) {
                    inpMedico.value = dados.medico;
                }

                detalheIdMedico.value = dados.id_medico; // Este existe sempre (hidden)
                detalheData.value = dados.data_iso;
                detalheDuracao.value = dados.duracao || 60;

                // MEMORIZAR HORA
                horaOriginalEdicao = dados.hora_iso;

                if (badge) {
                    badge.textContent = dados.estado.toUpperCase();
                    badge.className = dados.estado === 'finalizado' ? 'badge bg-success shadow-sm' : 'badge bg-white text-dark bg-opacity-75 shadow-sm badge-estado';
                }

                carregarSlotsEdicao(dados.id_medico, dados.data_iso, dados.hora_iso, dados.duracao, dados.id);

                btnCancel.href = `/cancelar_agendamento/${dados.id}`;

                const modal = new bootstrap.Modal(modalDetalhesEl);
                modal.show();
            }
        } catch (e) { console.error(e); }
    }

    async function carregarSlotsEdicao(medicoId, dataVal, horaAtualPreservar, duracaoVal, ignorarId) {
        if (!detalheHora) return;
        detalheHora.innerHTML = '<option disabled>A carregar...</option>';

        try {
            let url = `/api/horarios-disponiveis?medico=${medicoId}&data=${dataVal}&duracao=${duracaoVal}`;
            if (ignorarId) {
                url += `&ignorar_id=${ignorarId}`;
            }

            const response = await fetch(url);
            const horarios = await response.json();

            detalheHora.innerHTML = '';

            let mantivemosOriginal = false;

            horarios.forEach(hora => {
                const option = document.createElement('option');
                option.value = hora;
                option.textContent = hora;

                if (hora === horaAtualPreservar) {
                    option.textContent = `${hora} (Atual)`;
                    option.selected = true;
                    mantivemosOriginal = true;
                }

                detalheHora.appendChild(option);
            });

            if (detalheHora.options.length === 0) {
                detalheHora.innerHTML = '<option disabled>Sem vagas para esta duração</option>';
            }

        } catch (error) {
            detalheHora.innerHTML = '<option disabled>Erro</option>';
        }
    }

    // Listeners Edição
    if (detalheData) {
        detalheData.addEventListener('change', function () {
            carregarSlotsEdicao(detalheIdMedico.value, this.value, null, detalheDuracao.value, detalheId.value);
        });
    }

    if (detalheDuracao) {
        detalheDuracao.addEventListener('change', function () {
            // Usa a horaOriginalEdicao para tentar manter a seleção
            carregarSlotsEdicao(
                detalheIdMedico.value,
                detalheData.value,
                horaOriginalEdicao,
                this.value,
                detalheId.value
            );
        });
    }


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
            document.getElementById('newNif').value = '';
            document.getElementById('newNome').value = '';
            document.getElementById('newTel').value = '';
            document.getElementById('newData').value = '';
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
                    document.getElementById('newNif').value = '';
                    document.getElementById('newNome').value = '';
                    document.getElementById('newTel').value = '';
                    document.getElementById('newData').value = '';
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
    }

    // =========================================================
    // 6. LIMPAR MODAL AO CLICAR NO BOTÃO "NOVO AGENDAMENTO"
    // =========================================================
    const btnGlobal = document.getElementById('btnNovoAgendamentoGlobal');

    if (btnGlobal) {
        btnGlobal.addEventListener('click', function () {
            // 1. Limpar Data
            if (inputData) inputData.value = '';

            // 2. Resetar Duração
            if (selectDuracaoCriar) selectDuracaoCriar.value = "60";

            // 3. Resetar Horas (Voltar ao estado "--:--")
            if (selectHora) {
                selectHora.innerHTML = '<option value="" selected disabled>--:--</option>';
                selectHora.disabled = true;
                selectHora.classList.remove('is-valid'); // Remove o verde se tiver ficado
            }

            // 4. (Opcional) Se quiseres resetar o switch Online também
            if (checkOnline) checkOnline.checked = false;
        });
    }
});